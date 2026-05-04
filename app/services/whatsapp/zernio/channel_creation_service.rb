class Whatsapp::Zernio::ChannelCreationService
  def initialize(account:, phone_number:, account_id:, profile_id:,
                 api_key: nil, phone_number_id: nil, business_account_id: nil,
                 inbox_name: nil, inbox_id: nil)
    @account = account
    @phone_number = phone_number
    @account_id = account_id
    @profile_id = profile_id
    @api_key = api_key
    @phone_number_id = phone_number_id
    @business_account_id = business_account_id
    @inbox_name = inbox_name
    @inbox_id = inbox_id
  end

  def perform
    validate_parameters!

    if @inbox_id.present?
      reauthorize_existing_channel
    else
      create_new_channel
    end
  end

  private

  def validate_parameters!
    raise ArgumentError, 'Account is required' if @account.blank?
    raise ArgumentError, 'Phone number is required' if @phone_number.blank?
    raise ArgumentError, 'Zernio account_id is required' if @account_id.blank?
    raise ArgumentError, 'Zernio profile_id is required' if @profile_id.blank?
  end

  def reauthorize_existing_channel
    inbox = @account.inboxes.find(@inbox_id)
    channel = inbox.channel
    raise ArgumentError, 'Inbox is not a WhatsApp channel' unless channel.is_a?(Channel::Whatsapp)

    # Replace provider_config entirely (don't merge): the previous Meta-direct
    # credentials (api_key/phone_number_id/business_account_id/webhook_verify_token)
    # are stale by the time the user reauths via Zernio. Keeping them only adds
    # noise. Pattern matches Whatsapp::EmbeddedSignupService reauth.
    channel.assign_attributes(
      phone_number: @phone_number,
      provider_config: provider_config_payload
    )
    unless channel.save
      Rails.logger.error("[ZERNIO REAUTH] validation failed: #{channel.errors.full_messages.inspect}")
      Rails.logger.error("[ZERNIO REAUTH] provider_config=#{channel.provider_config.inspect}")
      raise ActiveRecord::RecordInvalid, channel
    end
    channel.reauthorized!
    channel
  end

  def create_new_channel
    existing_channel = Channel::Whatsapp.find_by(phone_number: @phone_number)
    raise I18n.t('errors.whatsapp.phone_number_already_exists', phone_number: existing_channel.phone_number) if existing_channel

    ActiveRecord::Base.transaction do
      channel = Channel::Whatsapp.create!(
        account: @account,
        phone_number: @phone_number,
        provider: 'whatsapp_cloud',
        provider_config: provider_config_payload
      )
      Inbox.create!(account: @account, name: inbox_name_for_create, channel: channel)
      channel
    end
  end

  def provider_config_payload
    payload = {
      'gateway' => 'zernio',
      'account_id' => @account_id,
      'profile_id' => @profile_id,
      'phone_number_id' => @phone_number_id,
      'business_account_id' => @business_account_id,
      # Marked as embedded_signup so all existing UI gates that hide manual
      # webhook details and show OAuth-style reauth banners apply transparently.
      'source' => 'embedded_signup'
    }
    # Only persist Meta token when direct-meta runtime is on; otherwise channel uses Zernio runtime.
    payload['api_key'] = @api_key if Whatsapp::Providers::ZernioService.direct_meta_enabled?
    payload.compact
  end

  def inbox_name_for_create
    @inbox_name.presence || "WhatsApp #{@phone_number}"
  end
end
