class Conversations::MarkMessageReadOnProviderService
  def initialize(conversation)
    @conversation = conversation
    @inbox = conversation.inbox
    @channel = @inbox.channel
  end

  def perform
    return unless channel_supports_mark_read?

    last_incoming_message = find_last_incoming_message
    return unless last_incoming_message&.source_id.present?

    Rails.logger.debug "[MARK MESSAGE READ] Starting - Channel: #{@channel.class}, Provider Service: #{provider_service.class}"
    provider_service.mark_message_read(last_incoming_message.source_id)
  end

  private

  def channel_supports_mark_read?
    return false unless @channel.respond_to?(:provider_service)

    provider_service.respond_to?(:mark_message_read)
  end

  def find_last_incoming_message
    @conversation.messages.incoming.order(created_at: :desc).first
  end

  def provider_service
    @provider_service ||= @channel.provider_service
  end
end

