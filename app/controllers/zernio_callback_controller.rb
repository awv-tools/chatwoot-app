class ZernioCallbackController < ApplicationController
  # GET /zernio/callback/:state?connected=whatsapp&profileId=…&step=…&tempToken=…&connect_token=…
  def show
    state = params[:state]
    cache_key = "zernio:oauth:state:#{state}"
    raw = ::Redis::Alfred.get(cache_key)
    cached = raw.present? ? JSON.parse(raw).with_indifferent_access : nil

    if cached.blank?
      Rails.logger.warn "[WHATSAPP][ZERNIO] callback received with unknown/expired state: #{state}"
      redirect_to '/' and return
    end

    ::Redis::Alfred.delete(cache_key)

    account = Account.find(cached[:account_id])
    phone = normalize_phone(params[:username])
    is_reauth = cached[:inbox_id].present?
    zernio_account = resolve_zernio_account(params[:accountId], cached[:profile_id], params[:username])

    channel = Whatsapp::Zernio::ChannelCreationService.new(
      account: account,
      phone_number: phone,
      account_id: zernio_account&.dig('_id'),
      profile_id: cached[:profile_id],
      phone_number_id: zernio_account&.dig('metadata', 'phoneNumberId'),
      business_account_id: zernio_account&.dig('metadata', 'wabaId'),
      inbox_name: is_reauth ? nil : build_inbox_name(cached[:account_name]),
      inbox_id: cached[:inbox_id]
    ).perform

    redirect_to redirect_after_creation(account, channel, is_reauth)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] callback error: #{e.class}: #{e.message}"
    redirect_to '/'
  end

  private

  # Zernio returns the phone formatted (e.g. "+55 81 7301-8420"); coerce to E.164.
  def normalize_phone(phone)
    return phone if phone.blank?

    digits = phone.to_s.gsub(/[^\d+]/, '')
    digits.start_with?('+') ? digits : "+#{digits}"
  end

  def build_inbox_name(account_name)
    "#{account_name} -> WhatsApp"
  end

  # Inbox novo entra no wizard padrão (/new/:id/agents → /new/:id/finish);
  # reauth vai pra aba de configuration com flag pra disparar toast de sucesso.
  def redirect_after_creation(account, channel, is_reauth)
    base = "/app/accounts/#{account.id}/settings/inboxes/#{channel.inbox.id}"
    return "#{base}/configuration?reauthorized=true" if is_reauth

    "/app/accounts/#{account.id}/settings/inboxes/new/#{channel.inbox.id}/agents"
  end

  # Busca a account inteira (não só id) pra extrair metadata como phoneNumberId/wabaId.
  # Filtra por profileId + username recém-conectado quando accountId não veio na URL (Zernio omite quando user tem múltiplas).
  def resolve_zernio_account(account_id_from_url, profile_id, username)
    accounts = Whatsapp::Providers::ZernioService.list_accounts
    return accounts.find { |a| a['_id'] == account_id_from_url } if account_id_from_url.present?

    accounts.find do |a|
      a.dig('profileId', '_id') == profile_id && a['username'] == username
    end
  end
end
