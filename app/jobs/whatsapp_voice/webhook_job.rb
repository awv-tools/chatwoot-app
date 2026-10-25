# Handles WhatsApp Cloud `calls` webhooks (call connect/terminate and call status events).
# Runs on the critical queue: Meta only waits ~30-60s for the business to answer a call.
class WhatsappVoice::WebhookJob < ApplicationJob
  queue_as :critical

  def perform(params)
    value = params.with_indifferent_access.dig(:entry, 0, :changes, 0, :value)
    channel = find_channel(value[:metadata])
    return Rails.logger.warn('[WHATSAPP_VOICE] calls webhook for unknown phone number') if channel.blank?

    WhatsappVoice::CallEventService.new(channel: channel, value: value).perform
  end

  private

  def find_channel(metadata)
    Whatsapp::WebhookChannelFinderService.new(
      display_phone_number: metadata[:display_phone_number],
      phone_number_id: metadata[:phone_number_id]
    ).perform
  end
end
