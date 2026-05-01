class Webhooks::ZernioEventsJob < ApplicationJob
  queue_as :low

  INCOMING_EVENT = 'message.received'.freeze
  OUTGOING_ECHO_EVENT = 'message.sent'.freeze
  STATUS_EVENTS = %w[message.delivered message.read message.failed].freeze

  def perform(params = {})
    params = params.with_indifferent_access if params.respond_to?(:with_indifferent_access)

    event = params[:event]
    account_id = params.dig(:account, :id)

    if account_id.blank?
      Rails.logger.warn "[WHATSAPP][ZERNIO] webhook without account.id (event=#{event})"
      return
    end

    channel = find_channel(account_id)
    if channel_inactive?(channel)
      Rails.logger.warn "[WHATSAPP][ZERNIO] inactive or unknown channel for accountId=#{account_id} (event=#{event})"
      return
    end

    case event
    when OUTGOING_ECHO_EVENT
      Whatsapp::IncomingMessageZernioService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform
    when INCOMING_EVENT, *STATUS_EVENTS
      Whatsapp::IncomingMessageZernioService.new(inbox: channel.inbox, params: params).perform
    else
      Rails.logger.info "[WHATSAPP][ZERNIO] ignored event=#{event}"
    end
  end

  private

  def find_channel(account_id)
    Channel::Whatsapp
      .where("provider_config ->> 'gateway' = ? AND provider_config ->> 'account_id' = ?", 'zernio', account_id)
      .first
  end

  def channel_inactive?(channel)
    return true if channel.blank?
    return true if channel.reauthorization_required?
    return true unless channel.account.active?

    false
  end
end
