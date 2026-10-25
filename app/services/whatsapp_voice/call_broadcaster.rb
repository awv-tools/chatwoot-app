# Sends the voice_call.* events the dashboard call UI listens to, account wide like the other call providers
module WhatsappVoice::CallBroadcaster
  def self.broadcast(message, event, **extra)
    ActionCable.server.broadcast(
      "account_#{message.account_id}",
      {
        event: "voice_call.#{event}",
        data: { id: message.source_id, call_id: message.source_id, provider: 'whatsapp', conversation_id: message.conversation.display_id,
                account_id: message.account_id }.merge(extra)
      }
    )
  end
end
