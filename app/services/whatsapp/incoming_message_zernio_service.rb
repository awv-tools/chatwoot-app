# Translates Zernio webhook payloads into the Cloud-API shape that
# Whatsapp::IncomingMessageBaseService already understands.
#
# Zernio events handled:
# - message.received  → messages + contacts (incoming)
# - message.sent      → message_echoes (outgoing echo, set outgoing_echo: true on construction)
# - message.delivered / message.read / message.failed → statuses
#
# After the base service creates/finds the conversation we persist the Zernio
# conversationId on Conversation#additional_attributes so outbound sends can
# reuse it (see Whatsapp::Providers::ZernioService#send_message).
class Whatsapp::IncomingMessageZernioService < Whatsapp::IncomingMessageBaseService
  STATUS_BY_EVENT = {
    'message.delivered' => 'delivered',
    'message.read' => 'read',
    'message.failed' => 'failed'
  }.freeze

  private

  def processed_params
    @processed_params ||= translate_payload.with_indifferent_access
  end

  def translate_payload
    case params[:event]
    when 'message.received'
      translate_inbound
    when 'message.sent'
      translate_echo
    when *STATUS_BY_EVENT.keys
      translate_status
    else
      {}
    end
  end

  def translate_inbound
    msg = params[:message] || {}
    sender = msg[:sender] || {}
    sender_id = sender[:id].to_s

    message_object = build_message_object(msg)
    referral = extract_ctwa_referral
    message_object['referral'] = referral if referral.present?

    {
      'messages' => [message_object],
      'contacts' => [{
        'wa_id' => sender_id,
        'profile' => { 'name' => sender[:name] }
      }]
    }
  end

  # Cloud API delivers Click-To-WhatsApp ad attribution inline on the message
  # (messages[0].referral). Zernio surfaces it on conversation.metadata with
  # ctwa_-prefixed keys instead. We translate to the Cloud shape so downstream
  # (analytics, automations, reports reading additional_attributes['referral'])
  # treats it identically across providers.
  #
  # Field mapping (Zernio → Cloud):
  #   ctwa_clid        → ctwa_clid          (same)
  #   ctwa_source_url  → source_url
  #   ctwa_source_id   → source_id
  #   ctwa_source_type → source_type
  #   ctwa_headline    → headline
  #   ctwa_captured_at → captured_at        (Zernio-specific, kept for traceability)
  def extract_ctwa_referral
    metadata = params.dig(:conversation, :metadata)
    return nil unless metadata.is_a?(Hash) && metadata[:ctwa_clid].present?

    {
      'ctwa_clid' => metadata[:ctwa_clid],
      'source_url' => metadata[:ctwa_source_url],
      'source_id' => metadata[:ctwa_source_id],
      'source_type' => metadata[:ctwa_source_type],
      'headline' => metadata[:ctwa_headline],
      'captured_at' => metadata[:ctwa_captured_at]
    }.compact
  end

  def translate_echo
    msg = params[:message] || {}
    conv = params[:conversation] || {}

    echo = build_message_object(msg)
    echo['to'] = conv[:participantId].to_s
    { 'message_echoes' => [echo] }
  end

  # Builds a Cloud-API-shaped message object from a Zernio message.
  # When attachments are present, type is the attachment kind and the text
  # (if any) becomes a caption inside the type payload.
  #
  # We use the WAMID (msg.platformMessageId) as the identifier because:
  #   1. ZernioService#send_message gets data.messageId in the response which
  #      IS the WAMID — that's what we store as source_id at send time. So
  #      using wamid here makes the find_message_by_source_id dedup match.
  #   2. WAMID is the stable WhatsApp-side identifier; status events also
  #      reference it consistently.
  # msg.id (Zernio's internal mongo id) is informational only.
  def build_message_object(msg)
    sender = msg[:sender] || {}
    base = {
      'id' => msg[:platformMessageId],
      'from' => sender[:id].to_s,
      'timestamp' => msg[:sentAt]
    }

    # Reply / quote: Zernio surfaces the quoted wamid on the top-level
    # `metadata.quotedMessageId`. Cloud expects it inline as `message.context.id`.
    # Translate so process_in_reply_to in the base service picks it up.
    quoted_wamid = params.dig(:metadata, :quotedMessageId)
    base['context'] = { 'id' => quoted_wamid } if quoted_wamid.present?

    attachments = msg[:attachments] || []
    if attachments.any?
      type, type_payload = build_attachment_type_payload(attachments.first, msg[:text])
      base['type'] = type
      base[type] = type_payload
    else
      base['type'] = 'text'
      base['text'] = { 'body' => msg[:text] }
    end

    base
  end

  def build_attachment_type_payload(attachment, caption)
    type = map_attachment_type(attachment[:type])
    payload = {
      'id' => attachment[:_id] || attachment[:id],
      'url' => attachment[:url]
    }
    payload['caption'] = caption if caption.present? && %w[image video document].include?(type)
    [type, payload]
  end

  # Zernio attachment.type values seen so far: image, video, audio, voice, sticker, file.
  # Cloud API type names: image, video, audio, sticker, document.
  def map_attachment_type(zernio_type)
    case zernio_type.to_s.downcase
    when 'image' then 'image'
    when 'video' then 'video'
    when 'audio', 'voice' then 'audio'
    when 'sticker' then 'sticker'
    else 'document'
    end
  end

  def translate_status
    msg = params[:message] || {}

    {
      'statuses' => [{
        # Use WAMID (matches what we stored as source_id at send time —
        # data.messageId in Zernio's send response is actually the wamid).
        'id' => msg[:platformMessageId],
        'status' => STATUS_BY_EVENT[params[:event]],
        'timestamp' => params[:statusAt] || params[:timestamp]
      }]
    }
  end

  # Ensure zernio_conversation_id is stamped on the Chatwoot Conversation so
  # outbound sends (Whatsapp::Providers::ZernioService) can target it.
  def set_conversation
    super
    return unless @conversation

    zernio_conversation_id = (params.dig(:message, :conversationId) || params.dig(:conversation, :id)).to_s
    return if zernio_conversation_id.blank?

    @conversation.additional_attributes ||= {}
    return if @conversation.additional_attributes['zernio_conversation_id'] == zernio_conversation_id

    @conversation.additional_attributes['zernio_conversation_id'] = zernio_conversation_id
    @conversation.save!
  end

  # Zernio surfaces media via two URL flavours:
  #   - Public temp URLs (host: media.zernio.com) — no auth, just download.
  #   - API URLs (host: zernio.com/api/...) — require Bearer ZERNIO_API_KEY.
  # We send the Bearer token whenever the URL is on the API host; sending it
  # to public URLs is harmless but unnecessary, so we keep it scoped.
  #
  # Note: media downloads intentionally skip PROXY_URL — auditing focuses on
  # outbound requests TO Zernio (send_message, templates, profile mgmt), not
  # on incoming media. Routing downloads through MITM also tripped over the
  # proxy CA cert without buying any debugging value.
  def download_attachment_file(attachment_payload)
    url = attachment_payload[:url] || attachment_payload['url']
    return if url.blank?

    headers = url.include?('zernio.com/api/') ? { 'Authorization' => "Bearer #{ENV.fetch('ZERNIO_API_KEY', '')}" } : {}
    Down.download(url, headers: headers)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] download attachment failed (url=#{url}): #{e.message}"
    nil
  end

  # Echo attachments arrive on `message.sent` events. Base service has a
  # Cloud-specific path (uses phone_number_id + Bearer); for Zernio we reuse
  # the same download routine as inbound attachments.
  def download_echo_attachment_file(attachment_payload)
    download_attachment_file(attachment_payload)
  end
end
