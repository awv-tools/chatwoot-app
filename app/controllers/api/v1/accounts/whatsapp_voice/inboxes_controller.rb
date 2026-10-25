class Api::V1::Accounts::WhatsappVoice::InboxesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  rescue_from CustomExceptions::WhatsappVoiceError, with: :render_error_response

  def enable
    authorize @inbox, :enable_whatsapp_calling?
    ::WhatsappVoice::CallingToggleService.new(channel: @inbox.channel).enable!
    head :ok
  end

  def disable
    authorize @inbox, :disable_whatsapp_calling?
    ::WhatsappVoice::CallingToggleService.new(channel: @inbox.channel).disable!
    head :ok
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.voice_calling_supported?

    render_could_not_create_error(I18n.t('errors.whatsapp_voice.not_supported'))
  end
end
