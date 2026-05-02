class Webhooks::ZernioController < ActionController::API
  before_action :verify_signature

  # POST /webhooks/zernio — single endpoint, accountId in payload routes to channel.
  def process_payload
    Webhooks::ZernioEventsJob.perform_later(params.to_unsafe_hash)
    head :created
  end

  private

  # HMAC-SHA256 over raw body using ZERNIO_WEBHOOK_SECRET (mandatory).
  def verify_signature
    secret = ENV.fetch('ZERNIO_WEBHOOK_SECRET', '')
    return reject_webhook if secret.blank?

    received = request.headers['X-Zernio-Signature'].to_s
    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)
    return if ActiveSupport::SecurityUtils.secure_compare(received, expected)

    reject_webhook
  end

  def reject_webhook
    Rails.logger.warn '[WHATSAPP][ZERNIO] Not allowed'
    head :unauthorized
  end
end
