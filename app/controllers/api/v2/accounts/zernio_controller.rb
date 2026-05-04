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

    redirect_url = "#{ENV.fetch('FRONTEND_URL', '')}/zernio/callback/#{state}"
    auth_url = Whatsapp::Providers::ZernioService.request_auth_url(
      profile_id: profile_id,
      redirect_url: redirect_url
    )
    render json: { authUrl: auth_url, state: state }
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] authorize error: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v2/accounts/:account_id/zernio/select_phone?state=<state>
  # Returns the cached phones list for the selection screen.
  def select_phone_data
    cached = read_state(params[:state])
    return render(json: { error: 'state not found or expired' }, status: :not_found) if cached.blank?

    render json: {
      phones: cached['phones'] || [],
      profile_id: cached['profile_id'],
      is_reauth: cached['inbox_id'].present?
    }
  end

  # POST /api/v2/accounts/:account_id/zernio/select_phone
  # Body: { state, phone_number_id, waba_id }
  # Finaliza com Zernio, cria channel/inbox, devolve { inbox_id, redirect_path }.
  def select_phone
    cached = read_state(params[:state])
    return render(json: { error: 'state not found or expired' }, status: :not_found) if cached.blank?

    picked = (cached['phones'] || []).find { |p| p['id'] == params[:phone_number_id] }
    return render(json: { error: 'phone_number_id not in available phones' }, status: :unprocessable_entity) if picked.blank?

    ::Redis::Alfred.delete(cache_key(params[:state]))

    inbox_id, redirect_path = finalize_zernio_selection(cached, picked)
    render json: { inbox_id: inbox_id, redirect_path: redirect_path }
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] select_phone error: #{e.class}: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def read_state(state)
    raw = ::Redis::Alfred.get(cache_key(state))
    raw.present? ? JSON.parse(raw) : nil
  end

  def finalize_zernio_selection(cached, picked)
    result = Whatsapp::Providers::ZernioService.select_phone_number_finalize(
      phone_number_id: picked['id'],
      profile_id: cached['profile_id'],
      temp_token: cached['temp_token'],
      waba_id: picked['wabaId']
    )

    account = Account.find(cached['account_id'])
    is_reauth = cached['inbox_id'].present?
    zernio_account_payload = result['account'] || {}
    username = zernio_account_payload['username'] || picked['display_phone_number']
    zernio_account_id = zernio_account_payload['accountId'] || ZernioCallbackController.lookup_account_id_by_username(cached['profile_id'], username)

    channel = Whatsapp::Zernio::ChannelCreationService.new(
      account: account,
      phone_number: ZernioCallbackController.normalize_phone(username),
      account_id: zernio_account_id,
      profile_id: cached['profile_id'],
      api_key: cached['temp_token'],
      phone_number_id: picked['id'],
      business_account_id: picked['wabaId'],
      inbox_name: is_reauth ? nil : "#{cached['account_name']} -> WhatsApp",
      inbox_id: cached['inbox_id']
    ).perform

    if Whatsapp::Providers::ZernioService.direct_meta_enabled?
      Whatsapp::Providers::ZernioService.override_meta_webhook(
        waba_id: picked['wabaId'],
        access_token: cached['temp_token'],
        callback_url: "#{webhook_base_url}/webhooks/whatsapp/#{channel.phone_number}",
        verify_token: channel.provider_config['webhook_verify_token']
      )
    end

    redirect_path = if is_reauth
                      "/app/accounts/#{account.id}/settings/inboxes/#{channel.inbox.id}/configuration?reauthorized=true"
                    else
                      "/app/accounts/#{account.id}/settings/inboxes/new/#{channel.inbox.id}/agents"
                    end

    [channel.inbox.id, redirect_path]
  end

  # Reauth reuses the channel's profile_id; new inbox (and Cloud→Zernio fallback) goes through find_or_create.
  def resolve_profile_id
    if params[:inbox_id].present?
      channel = Current.account.inboxes.find(params[:inbox_id]).channel
      channel.provider_config['profile_id'].presence ||
        Whatsapp::Providers::ZernioService.find_or_create_profile(prefix: profile_name_prefix)
    else
      Whatsapp::Providers::ZernioService.find_or_create_profile(prefix: profile_name_prefix)
    end
  end

  # Sem sufixo de canal — profile pode hospedar WA + IG + FB no futuro.
  def profile_name_prefix
    account_name = Current.account.name.presence
    account_name ? "#{account_name} -> Profile" : 'Profile'
  end

  def cache_key(state)
    "zernio:oauth:state:#{state}"
  end

  # WEBHOOK_URL is the public tunnel for Meta deliveries; FRONTEND_URL is the fallback.
  def webhook_base_url
    ENV['WEBHOOK_URL'].presence || ENV['FRONTEND_URL'].presence || ''
  end
end
