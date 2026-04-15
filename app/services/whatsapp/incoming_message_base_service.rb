# Mostly modeled after the intial implementation of the service based on 360 Dialog
# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/
class Whatsapp::IncomingMessageBaseService
  include ::Whatsapp::IncomingMessageServiceHelpers

  pattr_initialize [:inbox!, :params!, :outgoing_echo]

  RETRYABLE_ERROR_CODES = [131_026, 131_042].freeze
  MAX_WHATSAPP_RETRIES = 2
  WHATSAPP_RETRY_DELAY = 10.seconds

  def perform
    processed_params

    statuses = processed_params.try(:[], :statuses) || processed_params.try(:[], 'statuses')
    messages = processed_params.try(:[], :messages) || processed_params.try(:[], 'messages')
    message_echoes = processed_params.try(:[], :message_echoes) || processed_params.try(:[], 'message_echoes')

    if statuses.present?
      process_statuses
    elsif messages.present?
      process_messages
    elsif message_echoes.present?
      process_message_echoes
    else
      Rails.logger.warn 'WhatsApp webhook received but no processable content found (statuses, messages, or message_echoes/smb_message_echoes)'
    end
  end

  # Returns messages array for both regular messages and echo events
  def messages_data
    @processed_params&.dig(:messages) || @processed_params&.dig(:message_echoes)
  end

  private

  def process_messages
    # We don't support reactions & ephemeral message now, we need to skip processing the message
    # if the webhook event is a reaction or an ephermal message or an unsupported message.
    return if unprocessable_message_type?(message_type)

    # Multiple webhook event can be received against the same message due to misconfigurations in the Meta
    # business manager account. While we have not found the core reason yet, the following line ensure that
    # there are no duplicate messages created.
    messages_array = @processed_params[:messages] || @processed_params['messages']
    first_message = messages_array&.first
    message_id = first_message&.[](:id) || first_message&.[]('id')
    return if find_message_by_source_id(message_id) || message_under_process?

    set_contact
    return unless @contact

    ActiveRecord::Base.transaction do
      set_conversation
      create_messages
    end
  end

  def process_statuses
    statuses_array = @processed_params[:statuses] || @processed_params['statuses']
    status = statuses_array&.first
    return unless status

    status_id = status[:id] || status['id']
    return unless find_message_by_source_id(status_id)

    update_message_with_status(@message, status)
  rescue ArgumentError => e
    Rails.logger.error "Error while processing whatsapp status update #{e.message}"
  end

  def update_message_with_status(message, status)
    status_value = status[:status] || status['status']
    errors = status[:errors] || status['errors']

    message.status = status_value
    if status_value == 'failed' && errors.present?
      error = errors&.first
      error_code = error[:code] || error['code']
      error_title = error[:title] || error['title']
      message.external_error = "#{error_code}: #{error_title}"
      return if schedule_whatsapp_retry(message, error_code)
    end
    message.save!
  end

  def schedule_whatsapp_retry(message, error_code)
    return false unless RETRYABLE_ERROR_CODES.include?(error_code.to_i)

    retry_count = message.content_attributes.fetch(:whatsapp_auto_retry_count, 0).to_i
    return false if retry_count >= MAX_WHATSAPP_RETRIES

    message.content_attributes = message.content_attributes.merge(whatsapp_auto_retry_count: retry_count + 1)
    message.source_id = nil
    message.status = :sent
    message.save!
    SendReplyJob.set(wait: WHATSAPP_RETRY_DELAY).perform_later(message.id)
    true
  end

  def create_messages
    messages_array = @processed_params[:messages] || @processed_params['messages']
    message = messages_array.first
    log_error(message) && return if error_webhook_event?(message)

    process_in_reply_to(message)

    message_type == 'contacts' ? create_contact_messages(message) : create_regular_message(message)
  end

  def create_contact_messages(message)
    message['contacts'].each do |contact|
      # Pass source_id from parent message since contact objects don't have :id
      create_message(contact, source_id: message[:id])
      attach_contact(contact)
      attach_referral_data(message)
      attach_interactive_data(message)
      @message.save!
    end
  end

  def create_regular_message(message)
    create_message(message, source_id: message[:id])
    attach_files
    attach_location if message_type == 'location'
    attach_referral_data(message)
    attach_interactive_data(message)
    @message.save!
  end

  def set_contact
    contacts_array = @processed_params[:contacts] || @processed_params['contacts']
    contact_params = contacts_array&.first
    return if contact_params.blank?

    waid = processed_waid(contact_params[:wa_id] || contact_params['wa_id'])

    messages_array = @processed_params[:messages] || @processed_params['messages']
    from_number = messages_array.first[:from] || messages_array.first['from']

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: {
        name: contact_params.dig(:profile, :name) || contact_params.dig('profile', 'name'),
        phone_number: "+#{from_number}"
      }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    # Update existing contact name if ProfileName is available and current name is just phone number
    update_contact_with_profile_name(contact_params)
  end

  def set_conversation
    # if lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations
                                    .where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def attach_files
    return if %w[text button interactive location contacts].include?(message_type)

    messages_array = @processed_params[:messages] || @processed_params['messages']
    first_message = messages_array&.first
    attachment_payload = first_message&.[](message_type.to_sym) || first_message&.[](message_type)
    return unless attachment_payload

    @message.content ||= attachment_payload[:caption] || attachment_payload['caption']

    attachment_file = download_attachment_file(attachment_payload)
    return if attachment_file.blank?

    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      file: {
        io: attachment_file,
        filename: attachment_file.original_filename,
        content_type: attachment_file.content_type
      }
    )
  end

  def attach_location
    messages_array = @processed_params[:messages] || @processed_params['messages']
    first_message = messages_array&.first
    location = first_message&.[]('location') || first_message&.[](:location)
    return unless location

    location_name = location['name'] ? "#{location['name']}, #{location['address']}" : ''
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      coordinates_lat: location['latitude'],
      coordinates_long: location['longitude'],
      fallback_title: location_name,
      external_url: location['url']
    )
  end

  def attach_referral_data(message)
    # Normalize ad_attribution_details to referral if needed
    # Check both string and symbol keys since webhook data comes as JSON (strings)
    referral_data = message.dig(:referral) || message.dig('referral') || message.dig(:ad_attribution_details) || message.dig('ad_attribution_details')

    return unless referral_data.present?

    @message.additional_attributes ||= {}
    @message.additional_attributes['referral'] = referral_data
  end

  def attach_interactive_data(message)
    # Capture interactive replies (list_reply, button_reply, etc.)
    # Check both string and symbol keys since webhook data comes as JSON (strings)
    interactive_data = message.dig(:interactive) || message.dig('interactive')

    return unless interactive_data.present?

    @message.additional_attributes ||= {}
    @message.additional_attributes['interactive'] = interactive_data
  end

  def create_message(message, source_id: nil)
    message_id = source_id || message[:id] || message['id']
    @message = @conversation.messages.build(
      content: message_content(message),
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: message_id.to_s,
      in_reply_to_external_id: @in_reply_to_external_id
    )
  end

  def attach_contact(contact)
    phones = contact[:phones]
    phones = [{ phone: 'Phone number is not available' }] if phones.blank?

    name_info = contact['name'] || {}
    contact_meta = {
      firstName: name_info['first_name'],
      lastName: name_info['last_name']
    }.compact

    phones.each do |phone|
      @message.attachments.new(
        account_id: @message.account_id,
        file_type: file_content_type(message_type),
        fallback_title: phone[:phone].to_s,
        meta: contact_meta
      )
    end
  end

  def update_contact_with_profile_name(contact_params)
    profile_name = contact_params.dig(:profile, :name)
    return if profile_name.blank?
    return if @contact.name == profile_name

    # Only update if current name exactly matches the phone number or formatted phone number
    return unless contact_name_matches_phone_number?

    @contact.update!(name: profile_name)
  end

  def contact_name_matches_phone_number?
    messages_array = @processed_params[:messages] || @processed_params['messages']
    first_message = messages_array&.first
    from_number = first_message&.[](:from) || first_message&.[]('from')
    return false unless from_number

    phone_number = "+#{from_number}"
    formatted_phone_number = TelephoneNumber.parse(phone_number).international_number
    @contact.name == phone_number || @contact.name == formatted_phone_number
  end

  def process_message_echoes
    message_echoes_array = @processed_params[:message_echoes] || @processed_params['message_echoes']
    return if message_echoes_array.blank?

    message_echoes_array.each do |echo|
      process_single_echo(echo)
    end
  rescue StandardError => e
    Rails.logger.error "Error while processing whatsapp smb_message_echoes: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def process_single_echo(echo)
    echo_id = echo[:id] || echo['id']
    return if echo_id.blank?

    return if find_message_by_source_id(echo_id)
    return if message_under_process_for_echo?(echo_id)

    cache_message_source_id_in_redis_for_echo(echo_id)

    target_number = echo[:to] || echo['to']
    return if target_number.blank?

    waid = processed_waid(target_number)
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: {
        phone_number: "+#{target_number}"
      }
    ).perform

    return unless contact_inbox&.contact

    ActiveRecord::Base.transaction do
      set_conversation_for_echo(contact_inbox)
      create_echo_message(echo, contact_inbox)
      clear_message_source_id_from_redis_for_echo(echo_id)
    end
  rescue StandardError => e
    clear_message_source_id_from_redis_for_echo(echo_id) if echo_id.present?
    Rails.logger.error "Error processing echo #{echo_id}: #{e.message}"
    raise e
  end

  def create_echo_message(echo, contact_inbox)
    echo_id = echo[:id] || echo['id']
    echo_type = echo[:type] || echo['type']

    return if unprocessable_message_type?(echo_type)

    @conversation = find_or_create_conversation_for_echo(contact_inbox)

    message = @conversation.messages.build(
      content: extract_echo_content(echo),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      sender: echo_message_sender,
      source_id: echo_id.to_s
    )

    attach_echo_files(message, echo) unless %w[text button interactive location contacts].include?(echo_type)
    attach_echo_location(message, echo) if echo_type == 'location'

    message.save!
  end

  def echo_message_sender
    return @conversation.assignee if @conversation&.assignee.present?

    first_agent = @inbox.account.agents.first
    return first_agent if first_agent.present?

    first_admin = @inbox.account.administrators.first
    return first_admin if first_admin.present?

    @inbox.account.users.first
  end

  def extract_echo_content(echo)
    echo.dig(:text, :body) || echo.dig('text', 'body') ||
      echo.dig(:button, :text) || echo.dig('button', 'text') ||
      echo.dig(:interactive, :button_reply, :title) || echo.dig('interactive', 'button_reply', 'title') ||
      echo.dig(:interactive, :list_reply, :title) || echo.dig('interactive', 'list_reply', 'title')
  end

  def attach_echo_files(message, echo)
    echo_type = echo[:type] || echo['type']
    attachment_payload = echo[echo_type.to_sym] || echo[echo_type]
    return unless attachment_payload

    message.content ||= attachment_payload[:caption] || attachment_payload['caption']

    attachment_file = download_echo_attachment_file(attachment_payload)
    return if attachment_file.blank?

    message.attachments.new(
      account_id: message.account_id,
      file_type: file_content_type(echo_type),
      file: {
        io: attachment_file,
        filename: attachment_file.original_filename,
        content_type: attachment_file.content_type
      }
    )
  rescue StandardError => e
    Rails.logger.error "Error attaching echo file: #{e.message}"
  end

  def download_echo_attachment_file(attachment_payload)
    media_id = attachment_payload[:id] || attachment_payload['id']
    return if media_id.blank?

    if inbox.channel.provider == 'whatsapp_cloud'
      phone_number_id = inbox.channel.provider_config['phone_number_id']
      media_api_url = inbox.channel.media_url(media_id, phone_number_id)

      url_response = HTTParty.get(
        media_api_url,
        headers: inbox.channel.api_headers
      )

      if url_response.unauthorized?
        inbox.channel.authorization_error!
        return
      end

      return unless url_response.success?

      parsed_response = url_response.parsed_response
      media_download_url = parsed_response['url']
      return unless media_download_url

      Down.download(media_download_url, headers: inbox.channel.api_headers)
    else
      Down.download(inbox.channel.media_url(media_id), headers: inbox.channel.api_headers)
    end
  rescue Down::Error => e
    Rails.logger.error "WhatsApp echo media download failed for media_id #{media_id}: #{e.message}"
    nil
  end

  def attach_echo_location(message, echo)
    location = echo['location'] || echo[:location]
    return unless location

    location_name = location['name'] ? "#{location['name']}, #{location['address']}" : ''
    message.attachments.new(
      account_id: message.account_id,
      file_type: file_content_type('location'),
      coordinates_lat: location['latitude'],
      coordinates_long: location['longitude'],
      fallback_title: location_name,
      external_url: location['url']
    )
  end

  def find_or_create_conversation_for_echo(contact_inbox)
    conversation = if inbox.lock_to_single_conversation
                     contact_inbox.conversations.last
                   else
                     contact_inbox.conversations.where.not(status: :resolved).last
                   end

    return conversation if conversation

    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact.id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def set_conversation_for_echo(contact_inbox)
    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
    set_conversation
  end

  def message_under_process_for_echo?(echo_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: echo_id)
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis_for_echo(echo_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: echo_id)
    ::Redis::Alfred.setex(key, true, 300)
  end

  def clear_message_source_id_from_redis_for_echo(echo_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: echo_id)
    ::Redis::Alfred.delete(key)
  end
end
