class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :process_payload

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    return head :ok if webhook_fields_only?('tracking_events')

    # Calls are handled by our own WhatsappVoice flow, before the events job (and its enterprise overlay)
    if webhook_fields_only?('calls')
      WhatsappVoice::WebhookJob.perform_later(params.to_unsafe_hash)
    else
      Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
      # The events job drops call permission replies, so our flow notes them in the conversation
      WhatsappVoice::WebhookJob.perform_later(params.to_unsafe_hash) if call_permission_reply?
    end
    head :ok
  end

  private

  def webhook_fields_only?(field)
    return false unless params[:object] == 'whatsapp_business_account'

    webhook_changes.present? && webhook_changes.all? { |change| change[:field] == field }
  end

  def call_permission_reply?
    webhook_changes.any? do |change|
      Array(change.dig(:value, :messages)).any? { |message| message.dig(:interactive, :type) == 'call_permission_reply' }
    end
  end

  def webhook_changes
    @webhook_changes ||= params.fetch(:entry, []).flat_map { |entry| entry.fetch(:changes, []) }
  end

  def valid_token?(token)
    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end

  def meta_app_secrets
    [
      *channel_meta_app_secrets(whatsapp_channel),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def whatsapp_channel
    @whatsapp_channel ||= whatsapp_business_payload_channel || Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  def meta_signature_verification_required?
    return true if whatsapp_channel.blank?
    return false unless whatsapp_channel.provider == 'whatsapp_cloud'
    return true if channel_meta_app_secrets(whatsapp_channel).present?

    whatsapp_channel.provider_config['source'] == 'embedded_signup'
  end

  def whatsapp_business_payload_channel
    return unless params[:object] == 'whatsapp_business_account'

    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata)
    return if metadata.blank?

    Whatsapp::WebhookChannelFinderService.new(
      display_phone_number: metadata[:display_phone_number],
      phone_number_id: metadata[:phone_number_id]
    ).perform
  end

  def inactive_whatsapp_number?
    phone_number = params[:phone_number]
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
