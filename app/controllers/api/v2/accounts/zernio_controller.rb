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
    # Rails.cache is :null_store in dev — use Redis directly so the callback can read it.
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

  # On reauth (inbox_id present): reuse the channel's existing profile_id —
  # the profile already exists on Zernio's side, only the WhatsApp connection
  # needs to be re-established. If the channel was migrated from a non-Zernio
  # source and has no profile_id yet, fall back to creating a fresh one
  # named after the channel's phone number.
  #
  # On new inbox (no inbox_id): create a fresh Zernio profile. 1 profile == 1
  # WhatsApp connection on Zernio's side, so a new inbox always means a new
  # profile. The profile_id is held in Redis state and only persisted to
  # provider_config when the OAuth callback succeeds.
  def resolve_profile_id
    if params[:inbox_id].present?
      channel = Current.account.inboxes.find(params[:inbox_id]).channel
      channel.provider_config['profile_id'].presence ||
        Whatsapp::Providers::ZernioService.create_profile(name: channel.phone_number)
    else
      Whatsapp::Providers::ZernioService.create_profile(name: params[:inbox_name].presence || temporary_profile_name)
    end
  end

  # Created before OAuth, so we don't have phone yet. Account name is enough
  # to identify the customer in Zernio's dashboard during the OAuth window;
  # the callback rewrites this to the final "{Account} -> WhatsApp (+phone)".
  def temporary_profile_name
    account_name = Current.account.name.presence
    account_name ? "#{account_name} -> WhatsApp" : 'WhatsApp'
  end

  def cache_key(state)
    "zernio:oauth:state:#{state}"
  end
end
