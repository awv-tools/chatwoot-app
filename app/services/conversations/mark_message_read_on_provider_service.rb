class Conversations::MarkMessageReadOnProviderService
  def initialize(conversation)
    @conversation = conversation
    @inbox = conversation.inbox
    @channel = @inbox.channel
  end

  def perform
    return unless @channel.respond_to?(:provider_service)

    if provider_service.respond_to?(:mark_message_read, true)
      mark_via_dedicated_endpoint
    elsif provider_service.respond_to?(:fetch_conversation_messages, true)
      mark_via_fetch_side_effect
    end
  rescue StandardError
    nil
  end

  private

  # Cloud-style: provider has a real mark-as-read endpoint. We pass the WAMID
  # of the latest incoming message and the provider POSTs the read receipt.
  def mark_via_dedicated_endpoint
    last_incoming_message = find_last_incoming_message
    return unless last_incoming_message.present?

    provider_service.send(:mark_message_read, last_incoming_message.source_id)
  end

  # Zernio-style: provider has no mark-as-read endpoint, but their GET
  # conversation-messages call has the side effect of marking inbound messages
  # as read AND dispatching the WhatsApp read receipt. Until Zernio exposes a
  # real endpoint we lean on this side effect here.
  def mark_via_fetch_side_effect
    zernio_conv_id = @conversation.additional_attributes&.dig('zernio_conversation_id')
    return if zernio_conv_id.blank?

    provider_service.send(:fetch_conversation_messages, zernio_conv_id)
  end

  def find_last_incoming_message
    @conversation.messages.incoming.where.not(source_id: nil).reorder(created_at: :desc).first
  end

  def provider_service
    @provider_service ||= @channel.provider_service
  end
end
