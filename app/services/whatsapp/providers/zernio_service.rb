class Whatsapp::Providers::ZernioService < Whatsapp::Providers::BaseService
  # Bootstrap calls used by the OAuth flow before a Channel::Whatsapp exists.
  class << self
    def create_profile(name:)
      response = HTTParty.post(
        "#{api_base_path}/v1/profiles",
        request_options(headers: api_headers, body: { name: name }.to_json)
      )
      raise "Zernio profile creation failed (HTTP #{response.code})" unless response.success?

      response.parsed_response.dig('profile', '_id')
    end

    # headless=true returns OAuth data straight to our callback (Zernio's selection UI is skipped).
    def request_auth_url(profile_id:, redirect_url:)
      response = HTTParty.get(
        "#{api_base_path}/v1/connect/whatsapp",
        request_options(headers: api_headers, query: { profileId: profile_id, redirect_url: redirect_url, headless: true })
      )
      raise "Failed to obtain Zernio auth URL (HTTP #{response.code})" unless response.success?

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed['authUrl'] : nil
    end

    def fetch_pending_data(token:)
      response = HTTParty.get(
        "#{api_base_path}/v1/connect/pending-data",
        request_options(headers: { 'Content-Type' => 'application/json' }, query: { token: token })
      )
      raise "Zernio fetch_pending_data failed (HTTP #{response.code}): #{response.body}" unless response.success?

      response.parsed_response
    end

    def complete_connect(code:, state:, profile_id:, platform: 'whatsapp')
      response = HTTParty.post(
        "#{api_base_path}/v1/connect/#{platform}",
        request_options(headers: api_headers, body: { code: code, state: state, profileId: profile_id }.to_json)
      )
      raise "Zernio complete_connect failed (HTTP #{response.code}): #{response.body}" unless response.success?

      response.parsed_response
    end

    def update_profile(id:, name:)
      response = HTTParty.put(
        "#{api_base_path}/v1/profiles/#{id}",
        request_options(headers: api_headers, body: { name: name }.to_json)
      )
      raise "Zernio profile update failed (HTTP #{response.code})" unless response.success?

      response.parsed_response
    end

    def list_profiles
      response = HTTParty.get(
        "#{api_base_path}/v1/profiles",
        request_options(headers: api_headers)
      )
      raise "Zernio profile list failed (HTTP #{response.code})" unless response.success?

      response.parsed_response['profiles'] || []
    end

    def list_accounts
      response = HTTParty.get(
        "#{api_base_path}/v1/accounts",
        request_options(headers: api_headers)
      )
      raise "Zernio account list failed (HTTP #{response.code})" unless response.success?

      response.parsed_response['accounts'] || []
    end

    # Reusa profile órfão (prefix match + sem canais conectados) ou cria novo.
    def find_or_create_profile(prefix:)
      orphan = list_profiles.find do |p|
        p['name'].to_s.start_with?(prefix) && p['accountUsernames'].to_a.empty?
      end
      return orphan['_id'] if orphan

      id = create_profile(name: prefix)
      update_profile(id: id, name: "#{prefix}: #{id}")
      id
    end

    def list_phone_numbers(profile_id:, temp_token:)
      response = HTTParty.get(
        "#{api_base_path}/v1/connect/whatsapp/select-phone-number",
        request_options(headers: api_headers, query: { profileId: profile_id, tempToken: temp_token })
      )
      raise "Zernio list_phone_numbers failed (HTTP #{response.code}): #{response.body}" unless response.success?

      response.parsed_response['phoneNumbers'] || []
    end

    def select_phone_number_finalize(phone_number_id:, profile_id:, temp_token:, waba_id:)
      body = {
        phoneNumberId: phone_number_id,
        profileId: profile_id,
        tempToken: temp_token,
        wabaId: waba_id
      }
      response = HTTParty.post(
        "#{api_base_path}/v1/connect/whatsapp/select-phone-number",
        request_options(headers: api_headers, body: body.to_json)
      )
      raise "Zernio select_phone_number failed (HTTP #{response.code}): #{response.body}" unless response.success?

      response.parsed_response
    end

    # Direct override-only call — skips register (SMB-incompatible) and subscribe_app (Zernio already subscribed).
    def override_meta_webhook(waba_id:, access_token:, callback_url:, verify_token:)
      api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
      url = "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps"
      body = {
        override_callback_uri: callback_url,
        verify_token: verify_token
      }
      headers = {
        'Authorization' => "Bearer #{access_token}",
        'Content-Type' => 'application/json'
      }
      response = HTTParty.post(url, request_options(headers: headers, body: body.to_json))
      raise "Meta override failed (HTTP #{response.code}): #{response.body}" unless response.success?

      response.parsed_response
    end

    # Toggle: when true, runtime goes Meta-direct (Cloud API + override webhook).
    # When false (default), runtime goes through Zernio (send + receive).
    def direct_meta_enabled?
      ENV.fetch('ZERNIO_DIRECT_META', '') == 'true'
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

    # Optional MITM proxy; active whenever PROXY_URL is set (including production for debug).
    def http_options
      proxy = ENV.fetch('PROXY_URL', '')
      return {} if proxy.blank?

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
      { open_timeout: 5, read_timeout: 10 }.merge(options).merge(http_options)
    end
  end

  # Runtime methods below — dormant fallback, not called in current flow (channels with Meta api_key
  # route through WhatsappCloudService). Kept in case Zernio runtime is needed again.

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

  def send_template(_phone_number, template_info, message)
    @message = message

    return fail_missing_conversation_id(message) if zernio_conversation_id(message).blank?

    request_body = {
      accountId: account_id,
      template: {
        elements: [
          {
            name: template_info[:name],
            language: template_info[:lang_code],
            components: template_info[:parameters] || []
          }
        ]
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
    account_id.present? && ENV.fetch('ZERNIO_API_KEY', '').present?
  end

  def api_headers
    self.class.api_headers
  end

  def media_url(media_id, _phone_number_id = nil)
    "#{api_base_path}/v1/media/#{media_id}"
  end

  # data.messageId is the WAMID, matching message.platformMessageId in webhooks (used for echo dedup).
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

  # GET messages doubles as mark-as-read on Zernio (no dedicated endpoint). limit=1 since body is discarded.
  def fetch_conversation_messages(zernio_conv_id)
    return if zernio_conv_id.blank?

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

    # Stamp source_id immediately so webhook echo dedup works (echo can arrive in ms).
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
