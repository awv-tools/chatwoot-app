# Sends the voice_call.* events the dashboard call UI listens to, account wide like the other call providers
module WhatsappVoice::CallBroadcaster
  def self.broadcast(account_id, call_id, event, **extra)
    ActionCable.server.broadcast(
      "account_#{account_id}",
      { event: "voice_call.#{event}", data: { id: call_id, call_id: call_id, provider: 'whatsapp', account_id: account_id }.merge(extra) }
    )
  end
end
