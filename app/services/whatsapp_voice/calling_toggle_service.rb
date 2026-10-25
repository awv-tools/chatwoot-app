# Turns WhatsApp calling on or off for a whatsapp_cloud inbox, both at Meta and
# in the `calls` webhook subscription (driven by provider_config['calling_enabled']).
class WhatsappVoice::CallingToggleService
  pattr_initialize [:channel!]

  def enable!
    WhatsappVoice::MetaClient.new(channel: channel).update_calling_status('ENABLED')
    update_calling_flag(true)
  end

  def disable!
    WhatsappVoice::MetaClient.new(channel: channel).update_calling_status('DISABLED')
    update_calling_flag(false)
  end

  private

  def update_calling_flag(enabled)
    channel.provider_config = channel.provider_config.merge('calling_enabled' => enabled)
    Whatsapp::WebhookSetupService.new(channel).register_callback
    # Skip validate_provider_config: it re-checks credentials remotely and isn't relevant to this flag.
    channel.save!(validate: false)
  end
end
