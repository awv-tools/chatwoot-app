# Translates Zernio webhook payloads into Cloud-API shape for IncomingMessageBaseService.
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

  # Maps Zernio's conversation.metadata.ctwa_* keys to Cloud's message.referral shape.
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

  # Uses WAMID (platformMessageId) as id so it matches source_id stored on send (echo dedup).
  def build_message_object(msg)
    sender = msg[:sender] || {}
    base = {
      'id' => msg[:platformMessageId],
      'from' => sender[:id].to_s,
      'timestamp' => msg[:sentAt]
    }

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
        'id' => msg[:platformMessageId],
        'status' => STATUS_BY_EVENT[params[:event]],
        'timestamp' => params[:statusAt] || params[:timestamp]
      }]
    }
  end

  # Stamp zernio_conversation_id on Conversation so outbound sends can target it.
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

  # API-host URLs require Bearer ZERNIO_API_KEY; public media URLs need no auth.
  def download_attachment_file(attachment_payload)
    url = attachment_payload[:url] || attachment_payload['url']
    return if url.blank?

    headers = url.include?('zernio.com/api/') ? { 'Authorization' => "Bearer #{ENV.fetch('ZERNIO_API_KEY', '')}" } : {}
    Down.download(url, headers: headers)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] download attachment failed (url=#{url}): #{e.message}"
    nil
  end

  def download_echo_attachment_file(attachment_payload)
    download_attachment_file(attachment_payload)
  end

  # Echo via WhatsApp app: attribute to assignee, otherwise nil (renders as Bot).
  def echo_message_sender
    @conversation&.assignee
  end
end
