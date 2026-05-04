class Whatsapp::HealthService
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def fetch_health_status
    return fetch_zernio_health_data if @channel&.zernio_gateway? && !direct_meta_active?

    validate_channel!
    fetch_phone_health_data
  end

  private

  def direct_meta_active?
    Whatsapp::Providers::ZernioService.direct_meta_enabled? && @channel.provider_config['api_key'].present?
  end

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
  end

  def fetch_zernio_health_data
    account_id = @channel.provider_config['account_id']
    raise ArgumentError, 'Zernio account_id is missing' if account_id.blank?

    accounts = Whatsapp::Providers::ZernioService.list_accounts
    account = accounts.find { |a| a['_id'] == account_id }
    raise "Zernio account not found: #{account_id}" if account.blank?

    format_zernio_health(account)
  end

  # Mapeia o account do Zernio (com metadata) pra shape esperada pelo front (campos snake_case do Cloud).
  def format_zernio_health(data)
    return {} unless data.is_a?(Hash)

    metadata = data['metadata'] || {}
    {
      id: data['_id'],
      display_phone_number: metadata['displayPhoneNumber'] || data['username'],
      verified_name: metadata['verifiedName'] || data['displayName'],
      name_status: metadata['nameStatus'],
      quality_rating: metadata['qualityRating'],
      messaging_limit_tier: metadata['messagingLimitTier'],
      account_mode: data['isActive'] ? 'LIVE' : 'SANDBOX',
      platform_type: data['platform'],
      permissions: data['permissions'],
      business_id: metadata['wabaId'],
      gateway: 'zernio'
    }
  end

  def fetch_phone_health_data
    phone_number_id = @channel.provider_config['phone_number_id']

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      query: {
        fields: health_fields,
        access_token: @access_token
      }
    )

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise e
  end

  def health_fields
    %w[
      id
      quality_rating
      messaging_limit_tier
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      platform_type
      certificate
    ].join(',')
  end

  def handle_response(response)
    unless response.success?
      error_message = "WhatsApp API request failed: #{response.code} - #{response.body}"
      Rails.logger.error "[WHATSAPP HEALTH] #{error_message}"
      raise error_message
    end

    data = response.parsed_response
    format_health_response(data)
  end

  def format_health_response(response)
    {
      id: response['id'],
      display_phone_number: response['display_phone_number'],
      verified_name: response['verified_name'],
      name_status: response['name_status'],
      quality_rating: response['quality_rating'],
      messaging_limit_tier: response['messaging_limit_tier'],
      account_mode: response['account_mode'],
      code_verification_status: response['code_verification_status'],
      webhook_configuration: response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      throughput: response['throughput'],
      last_onboarded_time: response['last_onboarded_time'],
      platform_type: response['platform_type'],
      certificate: response['certificate'],
      business_id: @channel.provider_config['business_account_id']
    }
  end

  def build_expected_webhook_url
    base_url = ENV['WEBHOOK_URL'].presence || ENV['FRONTEND_URL'].presence
    return nil if base_url.blank?

    "#{base_url}/webhooks/whatsapp/#{@channel.phone_number}"
  end
end
