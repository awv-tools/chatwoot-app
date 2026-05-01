class Webhooks::ZernioController < ActionController::API
  before_action :verify_signature

  # POST /webhooks/zernio
  # Single static endpoint — Zernio webhook is configured once on their dashboard
  # and all events from all connected accounts arrive here. The accountId in the
  # payload body identifies which Channel::Whatsapp the event belongs to.
  def process_payload
    Webhooks::ZernioEventsJob.perform_later(params.to_unsafe_hash)
    head :created
  end

  private

  # HMAC-SHA256 over the raw body using ZERNIO_WEBHOOK_SECRET. Zernio sends the
  # digest in the X-Zernio-Signature header. We use the raw body (not parsed
  # params) because any reformatting changes byte order and breaks the digest.
  # secure_compare guards against timing attacks. The secret is mandatory in
  # all environments — without it the endpoint would accept forged webhooks.
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
