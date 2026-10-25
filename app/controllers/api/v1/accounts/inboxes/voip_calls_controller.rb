class Api::V1::Accounts::Inboxes::VoipCallsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  def accept
    authorize @inbox.channel.call_message(params[:id]).conversation, :show?

    response = client.claim_call(params[:id], agent_ref: Current.user.id)
    return render json: { join_uri: response['join_uri'] } if response.success?
    raise "Voice platform claim failed: #{response.code}" unless response.code == 409

    render json: { error: conflict_message(response['agent_ref']) }, status: :conflict
  end

  # 409 means the call is no longer ringing (answered, claimed or ended), which is what the agent wanted anyway
  def reject
    authorize @inbox.channel.call_message(params[:id]).conversation, :show?

    response = client.reject_call(params[:id])
    raise "Voice platform reject failed: #{response.code}" unless response.success? || response.code == 409

    head :no_content
  end

  def credentials
    response = client.agent_session(Current.user.id)
    raise "Voice platform session failed: #{response.code}" unless response.success?

    render json: response.parsed_response.slice('wss_url', 'sip_uri', 'username', 'password', 'ice_servers')
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.where(channel_type: 'Channel::Voip').find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def client
    @client ||= Voip::Client.new
  end

  def conflict_message(agent_ref)
    agent = Current.account.users.find_by(id: agent_ref) if agent_ref
    return I18n.t('errors.voice.call_no_longer_ringing') unless agent

    CustomExceptions::CallAlreadyAccepted.new(agent_name: agent.available_name).message
  end
end
