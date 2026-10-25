# Applies the events of a WhatsApp `calls` webhook to the voice_call message of each call.
class WhatsappVoice::CallEventService
  pattr_initialize [:channel!, :value!]

  def perform
    Array(value[:calls]).each do |call|
      case call[:event]
      when 'connect' then connect(call)
      when 'terminate' then terminate(call)
      end
    end
  end

  private

  def inbox
    @inbox ||= channel.inbox
  end

  def connect(call)
    return unless call[:direction] == 'USER_INITIATED'

    WhatsappVoice::IncomingCallService.new(inbox: inbox, value: value, call: call).perform
  end

  # Raises until the connect webhook has created the message, so a terminate processed first is retried
  def terminate(call)
    message = inbox.messages.voice_calls.find_by!(source_id: call[:id])
    status = final_status(message.call_data['status'])
    message.update_call_data!(status: status, duration_seconds: call[:duration], ended_at: Time.current.to_i)
    WhatsappVoice::CallBroadcaster.broadcast(message, :ended, status: status)
  end

  def final_status(status)
    case status
    when 'in-progress' then 'completed'
    when 'ringing' then 'no-answer'
    else status
    end
  end
end
