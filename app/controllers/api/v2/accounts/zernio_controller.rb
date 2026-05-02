class Api::V2::Accounts::ZernioController < Api::V1::Accounts::BaseController
  STATE_TTL = 10.minutes

  # POST /api/v2/accounts/:account_id/zernio/authorize
  def authorize
    profile_id = resolve_profile_id
    state = SecureRandom.hex(24)

    payload = {
      account_id: Current.account.id,
      account_name: Current.account.name,
      inbox_name: params[:inbox_name],
      inbox_id: params[:inbox_id],
      profile_id: profile_id
    }
    # Rails.cache is :null_store in dev — use Redis directly.
    ::Redis::Alfred.setex(cache_key(state), payload.to_json, STATE_TTL.to_i)

    redirect_url = "#{ENV.fetch('FRONTEND_URL', '')}/zernio/callback?cw_state=#{state}"
    auth_url = Whatsapp::Providers::ZernioService.request_auth_url(
      profile_id: profile_id,
      redirect_url: redirect_url
    )
    render json: { authUrl: auth_url, state: state }
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] authorize error: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Reauth reuses the channel's profile_id; new inbox creates a fresh profile.
  def resolve_profile_id
    if params[:inbox_id].present?
      channel = Current.account.inboxes.find(params[:inbox_id]).channel
      channel.provider_config['profile_id'].presence ||
        Whatsapp::Providers::ZernioService.create_profile(name: channel.phone_number)
    else
      Whatsapp::Providers::ZernioService.create_profile(name: params[:inbox_name].presence || temporary_profile_name)
    end
  end

  # Used before OAuth (no phone yet); callback rewrites to final "{Account} -> WhatsApp (+phone)".
  def temporary_profile_name
    account_name = Current.account.name.presence
    account_name ? "#{account_name} -> WhatsApp" : 'WhatsApp'
  end

  def cache_key(state)
    "zernio:oauth:state:#{state}"
  end
end
