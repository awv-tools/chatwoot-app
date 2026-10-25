# Notes the contact's answer to a call permission request in the conversation the request was sent from,
# so the agent knows whether to call again.
class WhatsappVoice::PermissionReplyService
  pattr_initialize [:inbox!, :message!]

  def perform
    # Replies that don't answer a request sent from the dashboard have no conversation to land in
    return if request.blank?

    request.conversation.messages.create!(account_id: inbox.account_id, inbox_id: inbox.id, message_type: :activity, content: content)
  end

  private

  def request
    context_id = message.dig(:context, :id)
    @request ||= inbox.messages.find_by(source_id: context_id) if context_id.present?
  end

  def content
    contact_name = request.conversation.contact.name
    I18n.with_locale(inbox.account.locale) do
      if message.dig(:interactive, :call_permission_reply, :response) == 'accept'
        I18n.t('conversations.activity.whatsapp_voice.call_permission_accepted', contact_name: contact_name)
      else
        I18n.t('conversations.activity.whatsapp_voice.call_permission_rejected', contact_name: contact_name)
      end
    end
  end
end
