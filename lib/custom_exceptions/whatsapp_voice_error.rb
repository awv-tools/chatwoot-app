class CustomExceptions::WhatsappVoiceError < CustomExceptions::Base
  def message
    @data[:message]
  end

  def code
    @data[:code]
  end

  def http_status
    :unprocessable_entity
  end
end
