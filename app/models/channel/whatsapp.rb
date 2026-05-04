# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number  (phone_number) UNIQUE
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud].freeze
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  def name
    'Whatsapp'
  end

  # Metadata marker only — identifies channels provisioned via Zernio (used by frontend reauth path).
  def zernio_gateway?
    provider_config.is_a?(Hash) && provider_config['gateway'] == 'zernio'
  end

  def provider_service
    return zernio_provider_service if zernio_gateway?
    return Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self) if provider == 'whatsapp_cloud'

    Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
  end

  def zernio_provider_service
    klass = direct_meta_active? ? Whatsapp::Providers::WhatsappCloudService : Whatsapp::Providers::ZernioService
    klass.new(whatsapp_channel: self)
  end

  # Direct-meta runtime requires the toggle on AND a usable Meta token on the channel.
  def direct_meta_active?
    Whatsapp::Providers::ZernioService.direct_meta_enabled? && provider_config['api_key'].present?
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service

  def setup_webhooks
    return if zernio_gateway?

    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    # Zernio channels need the token too — Meta validates override callback against it.
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud'
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    return if zernio_gateway?

    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    # Zernio gateway has its own webhook configured once on Zernio dashboard, not per channel
    return false if zernio_gateway?

    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end
end
