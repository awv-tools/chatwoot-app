# == Schema Information
#
# Table name: channel_voip
#
#  id             :bigint           not null, primary key
#  phone_number   :string           not null
#  webhook_secret :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :integer          not null
#  line_id        :string           not null
#
# Indexes
#
#  index_channel_voip_on_line_id       (line_id) UNIQUE
#  index_channel_voip_on_phone_number  (phone_number) UNIQUE
#

# Inbound calls from the self-hosted voice platform (VOIP_API_URL). Calls are stored as voice_call messages.
class Channel::Voip < ApplicationRecord
  include Channelable

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :webhook_secret if Chatwoot.encryption_configured?

  self.table_name = 'channel_voip'
  EDITABLE_ATTRS = [:phone_number].freeze
  WEBHOOK_TOLERANCE = 5.minutes

  # The line is registered on the voice platform for this number
  attr_readonly :phone_number

  validates :phone_number, presence: true, uniqueness: true
  validate :register_line, on: :create
  after_destroy_commit :release_line

  def name
    'Voip'
  end

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/voip"
  end

  def call_message(call_id)
    inbox.messages.voice_calls.find_by!(source_id: call_id)
  end

  def valid_webhook_signature?(body, timestamp, signature)
    return false if timestamp.blank? || signature.blank?
    return false if (Time.current.to_i - timestamp.to_i).abs > WEBHOOK_TOLERANCE

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, "#{timestamp}.#{body}")}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  # The voice platform transcribes calls itself; read by audio transcription when enterprise is loaded
  def transcription_enabled?
    false
  end

  private

  def register_line
    return if errors.any?

    response = ::Voip::Client.new.create_line(phone_number: phone_number, webhook_url: webhook_url)
    return errors.add(:phone_number, response['error'] || 'could not be registered') unless response.success?

    self.line_id = response['id']
    self.webhook_secret = response['webhook_secret']
  end

  def release_line
    ::Voip::Client.new.delete_line(line_id)
  end
end
