# LEGACY dedup, parked for audit and not included anywhere. Superseded by
# Whatsapp::IncomingMessageServiceHelpers#lock_message_source_id! (Whatsapp::MessageDedupLock),
# which owns the same Redis key but claims it atomically via SET NX.
module Whatsapp::LegacyMessageDedupHelpers
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
