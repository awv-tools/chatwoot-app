class ZernioCallbackController < ApplicationController
  STATE_TTL = 10.minutes

  # GET /zernio/callback/:state
  # Two modes:
  #  - headless (step=select_phone_number): tempToken returned; we list phones and auto-pick or show selection screen.
  #  - standard (no step): single-phone WABAs return accountId/username directly, no tempToken.
  def show
    cached = read_state(params[:state])
    return redirect_to('/') if cached.blank?

    if params[:step] == 'select_phone_number'
      handle_headless_callback(cached)
    else
      handle_standard_callback(cached)
    end
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] callback error: #{e.class}: #{e.message}"
    redirect_to '/'
  end

  def self.normalize_phone(phone)
    return phone if phone.blank?

    digits = phone.to_s.gsub(/[^\d+]/, '')
    digits.start_with?('+') ? digits : "+#{digits}"
  end

  # Fuzzy match: last-8-digit fallback covers Brazil 9-digit and formatting variants.
  def self.phone_match?(typed, candidate)
    typed_d = typed.to_s.gsub(/\D/, '')
    cand_d = candidate.to_s.gsub(/\D/, '')

    return true if typed_d == cand_d
    return true if typed_d.length >= 8 && cand_d.length >= 8 && typed_d[-8..] == cand_d[-8..]

    false
  end

  # WEBHOOK_URL is the public tunnel for Meta deliveries; FRONTEND_URL is the fallback.
  def self.webhook_base_url
    ENV['WEBHOOK_URL'].presence || ENV['FRONTEND_URL'].presence || ''
  end

  # Resolves accountId by filtering accounts list when Zernio response omits it.
  def self.lookup_account_id_by_username(profile_id, username)
    accounts = Whatsapp::Providers::ZernioService.list_accounts
    match = accounts.find do |a|
      a.dig('profileId', '_id') == profile_id && a['username'] == username
    end
    match&.dig('_id')
  end

  private

  def handle_headless_callback(cached)
    phones = Whatsapp::Providers::ZernioService.list_phone_numbers(
      profile_id: cached[:profile_id], temp_token: params[:tempToken]
    )

    auto_picked = pick_phone_or_nil(cached, phones)
    if auto_picked
      ::Redis::Alfred.delete("zernio:oauth:state:#{params[:state]}")
      redirect_to finalize_and_redirect(cached, auto_picked, params[:tempToken])
    else
      persist_extended_state(cached, phones)
      redirect_to "/app/accounts/#{cached[:account_id]}/whatsapp/select-phone/#{params[:state]}"
    end
  end

  # Standard mode: Zernio finished OAuth itself and posted accountId/username back. No tempToken available.
  def handle_standard_callback(cached)
    ::Redis::Alfred.delete("zernio:oauth:state:#{params[:state]}")
    account = Account.find(cached[:account_id])
    is_reauth = cached[:inbox_id].present?
    username = params[:username]
    zernio_account = lookup_zernio_account(params[:accountId], cached[:profile_id], username)

    channel = Whatsapp::Zernio::ChannelCreationService.new(
      account: account,
      phone_number: self.class.normalize_phone(username),
      account_id: zernio_account&.dig('_id') || params[:accountId],
      profile_id: cached[:profile_id],
      phone_number_id: zernio_account&.dig('metadata', 'phoneNumberId'),
      business_account_id: zernio_account&.dig('metadata', 'wabaId'),
      inbox_name: is_reauth ? nil : "#{cached[:account_name]} -> WhatsApp",
      inbox_id: cached[:inbox_id]
    ).perform

    redirect_to redirect_after_creation(account, channel, is_reauth)
  end

  def lookup_zernio_account(account_id, profile_id, username)
    accounts = Whatsapp::Providers::ZernioService.list_accounts
    accounts.find { |a| a['_id'] == account_id } ||
      accounts.find { |a| a.dig('profileId', '_id') == profile_id && a['username'] == username }
  end

  def redirect_after_creation(account, channel, is_reauth)
    if is_reauth
      "/app/accounts/#{account.id}/settings/inboxes/#{channel.inbox.id}/configuration?reauthorized=true"
    else
      "/app/accounts/#{account.id}/settings/inboxes/new/#{channel.inbox.id}/agents"
    end
  end

  def read_state(state)
    raw = ::Redis::Alfred.get("zernio:oauth:state:#{state}")
    if raw.blank?
      Rails.logger.warn "[WHATSAPP][ZERNIO] callback received with unknown/expired state: #{state}"
      return nil
    end
    JSON.parse(raw).with_indifferent_access
  end

  # Auto-pick when list has 1 phone, or in reauth when channel.phone matches one in the list.
  def pick_phone_or_nil(cached, phones)
    return phones.first if phones.size == 1
    return nil if cached[:inbox_id].blank?

    target_phone = Account.find(cached[:account_id]).inboxes.find(cached[:inbox_id]).channel.phone_number
    phones.find { |p| self.class.phone_match?(target_phone, p['display_phone_number']) }
  end

  def persist_extended_state(cached, phones)
    enriched = cached.merge(
      'phones' => phones,
      'temp_token' => params[:tempToken],
      'connect_token' => params[:connect_token]
    )
    ::Redis::Alfred.setex("zernio:oauth:state:#{params[:state]}", enriched.to_json, STATE_TTL.to_i)
  end

  # Transparent finalize when auto-pick succeeds (selection screen skipped).
  def finalize_and_redirect(cached, picked, temp_token)
    result = Whatsapp::Providers::ZernioService.select_phone_number_finalize(
      phone_number_id: picked['id'],
      profile_id: cached[:profile_id],
      temp_token: temp_token,
      waba_id: picked['wabaId']
    )

    account = Account.find(cached[:account_id])
    zernio_account_payload = result['account'] || {}
    username = zernio_account_payload['username'] || picked['display_phone_number']
    zernio_account_id = zernio_account_payload['accountId'] || self.class.lookup_account_id_by_username(cached[:profile_id], username)

    channel = Whatsapp::Zernio::ChannelCreationService.new(
      account: account,
      phone_number: self.class.normalize_phone(username),
      account_id: zernio_account_id,
      profile_id: cached[:profile_id],
      api_key: temp_token,
      phone_number_id: picked['id'],
      business_account_id: picked['wabaId'],
      inbox_name: nil,
      inbox_id: cached[:inbox_id]
    ).perform

    if Whatsapp::Providers::ZernioService.direct_meta_enabled?
      Whatsapp::Providers::ZernioService.override_meta_webhook(
        waba_id: picked['wabaId'],
        access_token: temp_token,
        callback_url: "#{self.class.webhook_base_url}/webhooks/whatsapp/#{channel.phone_number}",
        verify_token: channel.provider_config['webhook_verify_token']
      )
    end

    "/app/accounts/#{account.id}/settings/inboxes/#{channel.inbox.id}/configuration?reauthorized=true"
  end
end
