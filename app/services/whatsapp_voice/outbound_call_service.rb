# Places a call from an agent to the conversation's contact. Without the contact's call permission it sends
# the permission request instead, which Meta allows once every 24 hours.
class WhatsappVoice::OutboundCallService
  pattr_initialize [:conversation!, :agent!, :sdp_offer!]

  PERMISSION_REQUEST_INTERVAL = 24.hours

  def perform
    call_id = client.connect(recipient, sdp_offer)
    create_call_message(call_id)
    { id: call_id, call_id: call_id, conversation_id: conversation.display_id, recording_enabled: false }
  rescue CustomExceptions::WhatsappVoiceError => e
    raise unless e.code == WhatsappVoice::MetaClient::NO_PERMISSION_ERROR_CODE

    { status: request_permission, conversation_id: conversation.display_id }
  end

  private

  def client
    @client ||= WhatsappVoice::MetaClient.new(channel: conversation.inbox.channel)
  end

  def recipient
    conversation.contact_inbox.source_id
  end

  def create_call_message(call_id)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      sender: agent,
      content_type: :voice_call,
      content: I18n.t('conversations.messages.voice_call.whatsapp'),
      source_id: call_id,
      content_attributes: { 'data' => { 'call' => {
        'id' => call_id, 'provider_call_id' => call_id, 'provider' => 'whatsapp', 'direction' => 'outgoing', 'status' => 'ringing',
        'from_number' => conversation.inbox.channel.phone_number, 'to_number' => conversation.contact.phone_number
      } } }
    )
  end

  def request_permission
    key = format(Redis::RedisKeys::WHATSAPP_VOICE_CALL_PERMISSION_REQUESTED, contact_inbox_id: conversation.contact_inbox_id)
    return 'permission_pending' if Redis::Alfred.exists?(key)

    body = I18n.with_locale(conversation.account.locale) { I18n.t('conversations.messages.whatsapp.call_permission_request_body') }
    message_id = client.request_permission(recipient, body)
    # The source id keeps the request from being sent again as text, and lets the contact's reply find this conversation
    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  sender: agent, content: body, source_id: message_id)
    Redis::Alfred.setex(key, 1, PERMISSION_REQUEST_INTERVAL)
    'permission_requested'
  end
end
