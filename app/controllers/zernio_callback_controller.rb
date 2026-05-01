class ZernioCallbackController < ApplicationController
  # GET /zernio/callback
  # Zernio OAuth callback (per docs):
  #   ?connected=whatsapp&profileId=xxx&accountId=xxx&username=+1234567890
  # Plus our own cw_state appended via the redirect_url we passed to Zernio
  # (Zernio generates its own internal state and does not echo a state param back).
  # No Meta credentials are returned — Zernio handles all Meta interaction internally.
  # profile_id comes from the Redis state (created/looked up at authorize time),
  # not from the callback query — keeps it as the single source of truth.
  def show
    state = params[:cw_state]
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
    final_name = build_final_name(cached[:account_name], phone)

    # Best-effort rename on Zernio side — we already have the phone now, so the
    # profile gets a stable, human-readable label. Skipped on reauth: profile
    # already exists with whatever name the operator may have edited manually.
    rename_zernio_profile(cached[:profile_id], final_name) unless is_reauth

    channel = Whatsapp::Zernio::ChannelCreationService.new(
      account: account,
      phone_number: phone,
      account_id: params[:accountId],
      profile_id: cached[:profile_id],
      inbox_name: is_reauth ? nil : final_name,
      inbox_id: cached[:inbox_id]
    ).perform

    redirect_to "/app/accounts/#{account.id}/settings/inboxes/#{channel.inbox.id}"
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP][ZERNIO] callback error: #{e.class}: #{e.message}"
    redirect_to '/'
  end

  private

  # Zernio returns the phone with formatting (e.g. "+55 81 7301-8420").
  # Strip everything except digits + leading "+" so we land on E.164.
  def normalize_phone(phone)
    return phone if phone.blank?

    digits = phone.to_s.gsub(/[^\d+]/, '')
    digits.start_with?('+') ? digits : "+#{digits}"
  end

  def build_final_name(account_name, phone)
    account_name = account_name.presence
    account_name ? "#{account_name} -> WhatsApp (#{phone})" : "WhatsApp (#{phone})"
  end

  # Best-effort: failing to rename should not block channel creation. The inbox
  # in Chatwoot is created either way; Zernio profile keeps the temporary name
  # if the rename failed.
  def rename_zernio_profile(profile_id, name)
    return if profile_id.blank?

    Whatsapp::Providers::ZernioService.update_profile(id: profile_id, name: name)
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP][ZERNIO] profile rename failed (id=#{profile_id}): #{e.message}"
  end
end
