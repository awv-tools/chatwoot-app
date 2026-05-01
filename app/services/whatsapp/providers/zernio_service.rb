class Whatsapp::Providers::ZernioService < Whatsapp::Providers::BaseService
  # Bootstrap calls (no channel yet) — used by the OAuth flow before a
  # Channel::Whatsapp record exists. Profile creation is Zernio-specific
  # (1 profile == 1 WhatsApp number); other providers don't have this concept.
  class << self
    def create_profile(name:)
      response = HTTParty.post(
        "#{api_base_path}/v1/profiles",
        request_options(headers: api_headers, body: { name: name }.to_json)
      )
      raise "Zernio profile creation failed (HTTP #{response.code})" unless response.success?

      response.parsed_response.dig('profile', '_id')
    end

    def request_auth_url(profile_id:, redirect_url:)
      response = HTTParty.get(
        "#{api_base_path}/v1/connect/whatsapp",
        request_options(headers: api_headers, query: { profileId: profile_id, redirect_url: redirect_url })
      )
      raise "Failed to obtain Zernio auth URL (HTTP #{response.code})" unless response.success?

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed['authUrl'] : nil
    end

    # Renames a profile post-OAuth so the Zernio dashboard shows a meaningful
    # label including the connected phone. Caller is expected to rescue
    # StandardError if it wants best-effort behaviour — this method raises on
    # HTTP failure so tests can assert on it.
    def update_profile(id:, name:)
      response = HTTParty.patch(
        "#{api_base_path}/v1/profiles/#{id}",
        request_options(headers: api_headers, body: { name: name }.to_json)
      )
      raise "Zernio profile update failed (HTTP #{response.code})" unless response.success?

      response.parsed_response
    end

    def api_base_path
      ENV.fetch('ZERNIO_BASE_URL', 'https://zernio.com/api')
    end

    def api_headers
      {
        'Authorization' => "Bearer #{ENV.fetch('ZERNIO_API_KEY', '')}",
        'Content-Type' => 'application/json'
      }
    end

    # Optional HTTP proxy for Zernio requests only. Activated only when PROXY_URL
    # is set and Rails is not running in production (Rails.env comes from
    # RAILS_ENV/RACK_ENV). SSL verification is disabled because local MITM tools
    # intercept with their own CA, which Ruby won't trust by default. Malformed
    # URIs return {} silently — better to skip the proxy than to crash the request.
    def http_options
      proxy = ENV.fetch('PROXY_URL', '')
      return {} if proxy.blank? || Rails.env.production?

      uri = URI.parse(proxy)
      return {} if uri.host.blank?

      {
        http_proxyaddr: uri.host,
        http_proxyport: uri.port,
        http_proxyuser: uri.user,
        http_proxypass: uri.password,
        verify: false
      }.compact
    rescue URI::InvalidURIError
      {}
    end

    def request_options(options = {})
      options.merge(http_options)
    end
  end

  def send_message(_phone_number, message)
    @message = message

    return fail_missing_conversation_id(message) if zernio_conversation_id(message).blank?

    body =
      if message.attachments.present?
        attachment_body(message)
      elsif message.content_type == 'input_select'
        interactive_body(message)
      else
        text_body(message)
      end

    response = HTTParty.post(messages_url(message), request_options(headers: api_headers, body: body.to_json))
    process_response(response, message)
  end

  # Templates are sent through the same `/v1/inbox/conversations/:id/messages`
  # endpoint as regular messages — the difference is the body shape, which
  # mirrors Meta's Cloud API template object (name/language/components) wrapped
  # in Zernio's snake_case envelope (profile_id/to/channel/from). The /broadcasts
  # endpoint is for multi-recipient campaigns and is not the right semantic here.
  def send_template(_phone_number, template_info, message)
    @message = message

    return fail_missing_conversation_id(message) if zernio_conversation_id(message).blank?

    request_body = {
      accountId: account_id,
      template: {
        name: template_info[:name],
        language: template_info[:lang_code],
        components: template_info[:parameters] || []
      }
    }

    response = HTTParty.post(messages_url(message), request_options(headers: api_headers, body: request_body.to_json))
    process_response(response, message)
  end

  def toggle_typing_status(_status, conversation)
    conversation_id = conversation.additional_attributes&.dig('zernio_conversation_id')
    return if conversation_id.blank?

    HTTParty.post(
      "#{api_base_path}/v1/inbox/conversations/#{conversation_id}/typing",
      request_options(headers: api_headers, body: { accountId: account_id }.to_json)
    )
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP][ZERNIO] Typing indicator failed: #{e.message}"
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
    return if account_id.blank?

    response = HTTParty.get(
      "#{api_base_path}/v1/whatsapp/templates",
      request_options(headers: api_headers, query: { accountId: account_id })
    )

    unless response.success?
      Rails.logger.error "[WHATSAPP][ZERNIO] sync_templates HTTP #{response.code}"
      return
    end

    templates = extract_templates(response.parsed_response)
    return if templates.blank?

    whatsapp_channel.update!(message_templates: templates, message_templates_last_updated: Time.now.utc)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] sync_templates failed: #{e.message}"
  end

  def validate_provider_config?
    # Channel-side validation is just structural — the actual auth happens at the
    # Zernio gateway and is verified via the OAuth flow that produced the account_id.
    # Hitting an account introspection endpoint here would couple model save to a
    # remote round-trip and is not strictly necessary.
    account_id.present? && ENV.fetch('ZERNIO_API_KEY', '').present?
  end

  def api_headers
    self.class.api_headers
  end

  def media_url(media_id, _phone_number_id = nil)
    "#{api_base_path}/v1/media/#{media_id}"
  end

  # Zernio response shape: { success: true, data: { messageId, conversationId, sentAt, message } }
  # IMPORTANT: data.messageId here is the WAMID (Meta's platform message id),
  # not Zernio's internal mongo id. The webhook payload exposes the same WAMID
  # under message.platformMessageId — that is the field translate_*  uses for
  # dedup, so the source_id stored on send matches what the echo carries.
  def process_response(response, message)
    parsed = response.parsed_response
    if response.success? && parsed.is_a?(Hash) && parsed['success']
      data = parsed['data'] || {}
      persist_zernio_ids(message, data)
      data['messageId']
    else
      handle_error(response, message)
      nil
    end
  end

  private

  # Hits Zernio's GET conversation messages endpoint. Genuine purpose is
  # "fetch messages", but Zernio has no dedicated mark-as-read endpoint and
  # this GET happens to also flag inbound messages as read on their side
  # plus trigger the WhatsApp read receipt. Until they expose a real
  # mark-read endpoint, MarkMessageReadOnProviderService calls this here
  # specifically for that side effect.
  def fetch_conversation_messages(zernio_conv_id)
    return if zernio_conv_id.blank?

    # limit=1: we only need the side effect (mark-as-read + WhatsApp receipt).
    # The response body is discarded, so no point asking Zernio for more.
    HTTParty.get(
      "#{api_base_path}/v1/inbox/conversations/#{zernio_conv_id}/messages",
      request_options(headers: api_headers, query: { accountId: account_id, limit: 1 })
    )
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] fetch_conversation_messages error: #{e.message}"
  end

  def request_options(options = {})
    self.class.request_options(options)
  end

  # Zernio response for GET /v1/whatsapp/templates is documented as
  # `data.templates` via the SDK. Handle both top-level and nested shapes
  # to be resilient.
  def extract_templates(parsed)
    return nil unless parsed.is_a?(Hash)

    parsed['templates'] || parsed.dig('data', 'templates') || parsed['data']
  end

  def api_base_path
    self.class.api_base_path
  end

  def profile_id
    whatsapp_channel.provider_config['profile_id']
  end

  def account_id
    whatsapp_channel.provider_config['account_id']
  end

  def messages_url(message)
    "#{api_base_path}/v1/inbox/conversations/#{zernio_conversation_id(message)}/messages"
  end

  def zernio_conversation_id(message)
    message.conversation.additional_attributes&.dig('zernio_conversation_id')
  end

  def text_body(message)
    body = { accountId: account_id, message: message.outgoing_content }
    body[:replyTo] = reply_to(message) if reply_to(message).present?
    body
  end

  def attachment_body(message)
    attachment = message.attachments.first
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'file'

    body = {
      accountId: account_id,
      attachmentUrl: attachment.download_url,
      attachmentType: type
    }
    body[:message] = message.outgoing_content if message.outgoing_content.present?
    body[:replyTo] = reply_to(message) if reply_to(message).present?
    body
  end

  def interactive_body(message)
    items = message.content_attributes['items'] || []

    body =
      if items.length <= 3
        {
          accountId: account_id,
          message: message.outgoing_content,
          buttons: items.map { |item| { title: item['title'] } }
        }
      else
        {
          accountId: account_id,
          interactive: {
            type: 'list',
            body: { text: message.outgoing_content },
            action: {
              button: I18n.t('conversations.messages.whatsapp.list_button_label'),
              sections: [{ rows: items.map { |item| { id: item['value'], title: item['title'] } } }]
            }
          }
        }
      end

    body[:replyTo] = reply_to(message) if reply_to(message).present?
    body
  end

  def reply_to(message)
    message.content_attributes&.dig('in_reply_to_external_id')
  end

  def persist_zernio_ids(message, data)
    return if data.blank?

    conversation_id = data['conversationId']
    message_id = data['messageId']

    if conversation_id.present?
      conversation = message.conversation
      conversation.additional_attributes ||= {}
      conversation.additional_attributes['zernio_conversation_id'] ||= conversation_id
      conversation.save! if conversation.changed?
    end

    # Persist source_id and zernio_conversation_id on the message immediately —
    # not waiting for the caller — so the webhook echo (which can arrive in ms)
    # is correctly deduplicated via find_message_by_source_id.
    changes = false
    message.additional_attributes ||= {}
    if conversation_id.present? && message.additional_attributes['zernio_conversation_id'] != conversation_id
      message.additional_attributes['zernio_conversation_id'] = conversation_id
      changes = true
    end
    if message_id.present? && message.source_id != message_id
      message.source_id = message_id
      changes = true
    end
    message.save! if changes
  end

  def fail_missing_conversation_id(message)
    Rails.logger.warn(
      "[WHATSAPP][ZERNIO] send_message called without zernio_conversation_id (conversation #{message.conversation_id}). Send a template first."
    )
    message.update!(
      status: :failed,
      external_error: I18n.t(
        'errors.whatsapp.zernio.missing_conversation_id',
        default: 'Conversation not yet established with Zernio. Send a template first.'
      )
    )
    nil
  end

  def error_message(response)
    parsed = response.parsed_response
    return nil unless parsed.is_a?(Hash)

    parsed['error'] || parsed.dig('data', 'message') || parsed['message']
  end
end
