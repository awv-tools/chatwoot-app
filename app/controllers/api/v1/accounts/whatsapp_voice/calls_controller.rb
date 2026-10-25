# The Meta call id can hold characters that break a URL path, so it travels as the call_id parameter
class Api::V1::Accounts::WhatsappVoice::CallsController < Api::V1::Accounts::BaseController
  # Same STUN the browser uses for outbound calls, so it can reach Meta through NAT
  ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }].freeze

  before_action :fetch_message
  rescue_from CustomExceptions::WhatsappVoiceError, CustomExceptions::CallAlreadyAccepted, CustomExceptions::CallNoLongerRinging,
              with: :render_call_error

  # Read by the agent's browser to answer the call; recording is not supported yet
  def show
    sdp_offer = Redis::Alfred.get(format(Redis::RedisKeys::WHATSAPP_VOICE_SDP_OFFER, call_id: @message.source_id))
    render json: { id: @message.source_id, sdp_offer: sdp_offer, ice_servers: ICE_SERVERS, recording_enabled: false }
  end

  def accept
    WhatsappVoice::AcceptCallService.new(message: @message, agent: Current.user, sdp_answer: params.require(:sdp_answer)).perform
    head :ok
  end

  # The terminate webhook that follows ends the call for the other agents
  def reject
    meta_client.reject(@message.source_id)
    @message.update_call_data!(status: 'rejected', end_reason: 'agent_rejected')
    head :ok
  end

  def terminate
    meta_client.terminate(@message.source_id)
    head :ok
  end

  private

  def fetch_message
    whatsapp_inboxes = Current.account.inboxes.where(channel_type: 'Channel::Whatsapp')
    @message = Message.voice_calls.where(inbox: whatsapp_inboxes).find_by!(source_id: params.require(:call_id))
    authorize @message.conversation, :show?
  end

  def meta_client
    WhatsappVoice::MetaClient.new(channel: @message.inbox.channel)
  end

  def render_call_error(exception)
    render json: { error: exception.message }, status: exception.http_status
  end
end
