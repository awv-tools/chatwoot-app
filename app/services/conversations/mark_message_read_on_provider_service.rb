class Conversations::MarkMessageReadOnProviderService
  def initialize(conversation)
    @conversation = conversation
    @inbox = conversation.inbox
    @channel = @inbox.channel
  end

  def perform
    return unless channel_supports_mark_read?

    last_incoming_message = find_last_incoming_message
    return unless last_incoming_message.present?

    provider_service.send(:mark_message_read, last_incoming_message.source_id)
  end

  private

  def channel_supports_mark_read?
    return false unless @channel.respond_to?(:provider_service)

    service = provider_service
    service.respond_to?(:mark_message_read, true)
  rescue StandardError
    false
  end

  def find_last_incoming_message
    @conversation.messages.incoming.where.not(source_id: nil).reorder(created_at: :desc).first
  end

  def provider_service
    @provider_service ||= @channel.provider_service
  end
end

