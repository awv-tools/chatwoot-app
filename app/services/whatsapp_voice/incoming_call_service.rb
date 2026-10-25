# Opens the voice_call message of a call a contact places to the business; its message.created rings the inbox agents.
class WhatsappVoice::IncomingCallService
  include ::Whatsapp::IncomingMessageServiceHelpers
  include ::Whatsapp::IncomingMessageIdentifierHelper

  pattr_initialize [:inbox!, :value!, :call!]

  # Meta stops ringing after about a minute, so the offer is useless well before this
  SDP_OFFER_TTL = 5.minutes

  def perform
    return if inbox.messages.voice_calls.exists?(source_id: call[:id])

    # Stored before the message rings, since the agent's browser reads it when answering
    Redis::Alfred.setex(format(Redis::RedisKeys::WHATSAPP_VOICE_SDP_OFFER, call_id: call[:id]), call.dig(:session, :sdp), SDP_OFFER_TTL)
    create_message
  end

  private

  # The contact is resolved like an incoming message's, so a call lands on the same contact and conversation
  def contact_inbox
    @contact_inbox ||= begin
      contact_params = value[:contacts]&.first || {}
      source_ids = incoming_message_source_ids(contact_params)
      find_or_create_contact_inbox(
        source_ids: source_ids,
        contact_attributes: contact_attributes_from_contact_params(contact_params, source_ids.first)
      )
    end
  end

  def messages_data
    [call]
  end

  def conversation
    conversations = contact_inbox.conversations
    existing = inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
    existing || Conversation.create!(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact_inbox.contact_id,
                                     contact_inbox_id: contact_inbox.id)
  end

  def create_message
    conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      content_type: :voice_call,
      content: I18n.t('conversations.messages.voice_call.whatsapp'),
      source_id: call[:id],
      content_attributes: { 'data' => { 'call' => initial_call } }
    )
  end

  def initial_call
    {
      'id' => call[:id],
      'provider_call_id' => call[:id],
      'provider' => 'whatsapp',
      'direction' => 'incoming',
      'status' => 'ringing',
      'from_number' => contact_inbox.contact.phone_number,
      'to_number' => inbox.channel.phone_number
    }
  end
end
