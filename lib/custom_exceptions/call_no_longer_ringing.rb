# frozen_string_literal: true

class CustomExceptions::CallNoLongerRinging < CustomExceptions::Base
  def message
    I18n.t('errors.voice.call_no_longer_ringing')
  end

  def http_status
    409
  end
end
