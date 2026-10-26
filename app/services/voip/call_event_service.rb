class Voip::CallEventService
  pattr_initialize [:channel!, :payload!]

  EVENTS = %w[call.ai_answered call.ringing call.ai_resumed call.answered call.ended call.recording_ready call.transcribed].freeze

  def perform
    return unless EVENTS.include?(payload['event'])

    send(payload['event'].delete_prefix('call.'))
  end

  private

  def inbox
    @inbox ||= channel.inbox
  end

  def message
    @message ||= channel.call_message(payload['call_id'])
  end

  # The AI attendant answered the call; it may later ring for the agents as a transfer
  def ai_answered
    create_call_message('ai')
  end

  def ringing
    return create_call_message('ringing') if payload['transfer'].blank?

    message.update_call_data!(status: 'ringing', transfer_reason: payload['transfer']['reason'],
                              transfer_summary: payload['transfer']['summary'])
  end

  # Nobody answered the transfer, so the AI attendant took the call back
  def ai_resumed
    message.update_call_data!(status: 'ai')
  end

  def create_call_message(status)
    return if inbox.messages.voice_calls.exists?(source_id: payload['call_id'])

    contact_inbox = find_or_create_contact_inbox
    conversation = find_or_create_conversation(contact_inbox)
    conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      content_type: :voice_call,
      content: I18n.t('conversations.messages.voice_call.voip'),
      source_id: payload['call_id'],
      content_attributes: { 'data' => { 'call' => initial_call(status) } }
    )
  end

  def answered
    agent = inbox.account.users.find(payload['agent_ref'])
    message.conversation.update!(assignee: agent)
    message.update_call_data!(status: 'in-progress', accepted_by_agent_id: agent.id, accepted_by_agent_name: agent.available_name,
                              started_at: Time.current.to_i)
    broadcast(:accepted, accepted_by_agent_id: agent.id)
  end

  def ended
    message.update_call_data!(status: payload['status'], duration_seconds: payload['duration_seconds'], end_reason: payload['end_reason'],
                              ended_at: Time.current.to_i)
    broadcast(:ended, status: payload['status'])
    return if payload['ai_note'].blank?

    Messages::MessageBuilder.new(
      nil, message.conversation, { content: I18n.t('conversations.messages.voice_call.voip_ai_note', note: payload['ai_note']), private: true }
    ).perform
  end

  def recording_ready
    Channels::Voip::RecordingDownloadJob.perform_later(message)
  end

  def transcribed
    message.attachments.audio.first&.update!(meta: { 'transcribed_text' => payload['transcript'] })
    message.update_call_data!(transcript: payload['transcript'], transcript_segments: payload['segments'])
    return if payload['summary'].blank?

    Messages::MessageBuilder.new(
      nil, message.conversation, { content: I18n.t('conversations.messages.voice_call.voip_summary', summary: payload['summary']), private: true }
    ).perform
  end

  def find_or_create_contact_inbox
    from = payload['from']
    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: from || "anonymous:#{payload['call_id']}",
      contact_attributes: if from
                            { name: TelephoneNumber.parse(from).international_number, phone_number: from,
                              phone_number_candidates: phone_number_variants(from) }
                          else
                            { name: I18n.t('conversations.messages.voice_call.unknown_caller') }
                          end
    ).perform
  end

  # A Brazilian mobile may be saved without its ninth digit, as WhatsApp keeps legacy numbers
  def phone_number_variants(number)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).phone_number_candidates(number.delete_prefix('+'))
                                             .drop(1).map { |candidate| "+#{candidate}" }
  end

  def find_or_create_conversation(contact_inbox)
    conversations = contact_inbox.conversations
    conversation = inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
    conversation || Conversation.create!(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact_inbox.contact_id,
                                         contact_inbox_id: contact_inbox.id)
  end

  def initial_call(status)
    {
      'id' => payload['call_id'],
      'provider_call_id' => payload['call_id'],
      'provider' => 'voip',
      'direction' => 'incoming',
      'status' => status,
      'from_number' => payload['from'],
      'to_number' => channel.phone_number
    }
  end

  def broadcast(event, **extra)
    ActionCable.server.broadcast(
      "account_#{message.account_id}",
      {
        event: "voice_call.#{event}",
        data: { id: payload['call_id'], call_id: payload['call_id'], provider: 'voip', conversation_id: message.conversation.display_id,
                account_id: message.account_id }.merge(extra)
      }
    )
  end
end
