# Applies the events of a WhatsApp `calls` webhook to the voice_call message of each call.
class WhatsappVoice::CallEventService
  pattr_initialize [:channel!, :value!]

  def perform
    Array(value[:calls]).each { |call| call[:event] == 'connect' ? connect(call) : terminate(call) }
    Array(value[:statuses]).each { |status| outbound_status(status) }
    Array(value[:messages]).each do |message|
      WhatsappVoice::PermissionReplyService.new(inbox: inbox, message: message).perform if message.dig(:interactive, :type) == 'call_permission_reply'
    end
  end

  private

  def inbox
    @inbox ||= channel.inbox
  end

  def connect(call)
    return WhatsappVoice::IncomingCallService.new(inbox: inbox, value: value, call: call).perform if call[:direction] == 'USER_INITIATED'

    # Meta's answer to the agent's offer; it can land before initiate has stored the call, so it doesn't need the message
    WhatsappVoice::CallBroadcaster.broadcast(inbox.account_id, call[:id], :outbound_connected, sdp_answer: call.dig(:session, :sdp))
  end

  # Raises until the call's message exists, so an event processed before it is retried
  def terminate(call)
    message = call_message(call[:id])
    status = final_status(message.call_data['status'])
    message.update_call_data!(status: status, duration_seconds: call[:duration], ended_at: Time.current.to_i)
    WhatsappVoice::CallBroadcaster.broadcast(inbox.account_id, call[:id], :ended, status: status)
  end

  # RINGING needs nothing: the call already shows as ringing for the agent who placed it
  def outbound_status(status)
    case status[:status]
    when 'ACCEPTED'
      call_message(status[:id]).update_call_data!(status: 'in-progress', started_at: Time.current.to_i)
      WhatsappVoice::CallBroadcaster.broadcast(inbox.account_id, status[:id], :outbound_accepted)
    when 'REJECTED'
      call_message(status[:id]).update_call_data!(status: 'rejected')
    end
  end

  def call_message(call_id)
    inbox.messages.voice_calls.find_by!(source_id: call_id)
  end

  def final_status(status)
    case status
    when 'in-progress' then 'completed'
    when 'ringing' then 'no-answer'
    else status
    end
  end
end
