class Webhooks::VoipController < ActionController::API
  # Handled inline: the voice platform sends a call's events in order and waits for the 2xx
  def process_payload
    channel = Channel::Voip.find_by!(line_id: payload['line_id'])
    signature_valid = channel.valid_webhook_signature?(request.raw_post, request.headers['X-Voip-Timestamp'], request.headers['X-Voip-Signature'])
    return head :unauthorized unless signature_valid

    Voip::CallEventService.new(channel: channel, payload: payload).perform
    head :ok
  end

  private

  def payload
    @payload ||= JSON.parse(request.raw_post)
  end
end
