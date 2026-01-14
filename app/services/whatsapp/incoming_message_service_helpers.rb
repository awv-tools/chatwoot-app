module Whatsapp::IncomingMessageServiceHelpers
  def download_attachment_file(attachment_payload)
    media_id = attachment_payload[:id] || attachment_payload['id']
    return if media_id.blank?

    Down.download(inbox.channel.media_url(media_id), headers: inbox.channel.api_headers)
  rescue Down::Error => e
    Rails.logger.error "WhatsApp media download failed for media_id #{media_id}: #{e.message}"
    nil
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_array = @processed_params[:messages] || @processed_params['messages']
    message = messages_array.first
    message[:type] || message['type']
  end

  def message_content(message)
    # TODO: map interactive messages back to button messages in chatwoot
    # Try both symbol and string keys
    message.dig(:text, :body) || message.dig('text', 'body') ||
      message.dig(:button, :text) || message.dig('button', 'text') ||
      message.dig(:interactive, :button_reply, :title) || message.dig('interactive', 'button_reply', 'title') ||
      message.dig(:interactive, :list_reply, :title) || message.dig('interactive', 'list_reply', 'title') ||
      message.dig(:name, :formatted_name) || message.dig('name', 'formatted_name')
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    %w[reaction ephemeral unsupported request_welcome].include?(message_type)
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def error_webhook_event?(message)
    message.key?('errors') || message.key?(:errors)
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    context = message[:context] || message['context']
    @in_reply_to_external_id = context&.[]('id') || context&.[](:id) if context
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = Message.find_by(source_id: source_id)
  end

  def message_under_process?
    messages_array = @processed_params[:messages] || @processed_params['messages']
    first_message = messages_array&.first
    message_id = first_message&.[](:id) || first_message&.[]('id')
    return false unless message_id

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis
    messages_array = @processed_params[:messages] || @processed_params['messages']
    return if messages_array.blank?

    first_message = messages_array.first
    message_id = first_message[:id] || first_message['id']
    return unless message_id

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    ::Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    messages_array = @processed_params[:messages] || @processed_params['messages']
    first_message = messages_array&.first
    message_id = first_message&.[](:id) || first_message&.[]('id')
    return unless message_id

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    ::Redis::Alfred.delete(key)
  end
end
