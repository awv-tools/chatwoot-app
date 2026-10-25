# Thin client for the WhatsApp Cloud Calling API.
# https://developers.facebook.com/documentation/business-messaging/whatsapp/calling
class WhatsappVoice::MetaClient
  pattr_initialize [:channel!]

  NO_PERMISSION_ERROR_CODE = 138_006

  def update_calling_status(status)
    post('settings', { calling: { status: status } })
  end

  def pre_accept(call_id, sdp_answer)
    call_action(call_id, 'pre_accept', session: { sdp_type: 'answer', sdp: sdp_answer })
  end

  def accept(call_id, sdp_answer)
    call_action(call_id, 'accept', session: { sdp_type: 'answer', sdp: sdp_answer })
  end

  def reject(call_id)
    call_action(call_id, 'reject')
  end

  def terminate(call_id)
    call_action(call_id, 'terminate')
  end

  # Returns the Meta call id of the new business-initiated call.
  def connect(recipient, sdp_offer)
    response = post('calls', {
                      messaging_product: 'whatsapp',
                      **recipient_params(recipient),
                      action: 'connect',
                      session: { sdp_type: 'offer', sdp: sdp_offer }
                    })
    response.dig('calls', 0, 'id')
  end

  def request_permission(recipient, body_text)
    response = post('messages', {
                      messaging_product: 'whatsapp',
                      recipient_type: 'individual',
                      **recipient_params(recipient),
                      type: 'interactive',
                      interactive: {
                        type: 'call_permission_request',
                        action: { name: 'call_permission_request' },
                        body: { text: body_text }
                      }
                    })
    response.dig('messages', 0, 'id')
  end

  private

  def call_action(call_id, action, extra = {})
    post('calls', { messaging_product: 'whatsapp', call_id: call_id, action: action, **extra })
  end

  def post(path, body)
    response = HTTParty.post("#{phone_number_path}/#{path}", headers: headers, body: body.to_json)
    return response.parsed_response if response.success?

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    raise CustomExceptions::WhatsappVoiceError.new(code: error&.dig('code'), message: error&.dig('message') || response.body)
  end

  def recipient_params(recipient)
    recipient.to_s.match?(RegexHelper::WHATSAPP_BSUID_REGEX) ? { recipient: recipient } : { to: recipient }
  end

  def headers
    { 'Authorization' => "Bearer #{channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def phone_number_path
    base_url = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v24.0')
    "#{base_url}/#{version}/#{channel.provider_config['phone_number_id']}"
  end
end
