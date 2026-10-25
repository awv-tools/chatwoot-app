# Answers a ringing WhatsApp call for an agent. The row lock, held through the Meta calls, lets only one agent take it.
class WhatsappVoice::AcceptCallService
  pattr_initialize [:message!, :agent!, :sdp_answer!]

  def perform
    message.with_lock do
      ensure_ringing!
      answer_on_meta
      message.update_call_data!(status: 'in-progress', accepted_by_agent_id: agent.id, accepted_by_agent_name: agent.available_name,
                                started_at: Time.current.to_i)
    end
    message.conversation.update!(assignee: agent)
    WhatsappVoice::CallBroadcaster.broadcast(message, :accepted, accepted_by_agent_id: agent.id)
  end

  private

  def answer_on_meta
    client = WhatsappVoice::MetaClient.new(channel: message.inbox.channel)
    client.pre_accept(message.source_id, sdp_answer)
    client.accept(message.source_id, sdp_answer)
  end

  def ensure_ringing!
    call = message.call_data
    return if call['status'] == 'ringing'
    raise CustomExceptions::CallAlreadyAccepted.new(agent_name: call['accepted_by_agent_name']) if call['accepted_by_agent_name']

    raise CustomExceptions::CallNoLongerRinging, {}
  end
end
