class Whatsapp::TemplateSnapshotBuilder
  pattr_initialize [:template!, :processed_params]

  def perform
    snapshot = { header: header, footer: component('FOOTER')&.dig('text'), buttons: buttons }.compact
    snapshot.presence
  end

  private

  def header
    header_component = component('HEADER')
    return if header_component.blank?

    header_params = params['header'] || {}
    if header_component['format'] == 'TEXT'
      { format: 'TEXT', text: substitute(header_component['text'], header_params) }
    else
      { format: header_component['format'], media_url: header_params['media_url'], media_name: header_params['media_name'] }.compact
    end
  end

  def buttons
    template_buttons = component('BUTTONS')&.dig('buttons')
    return if template_buttons.blank?

    button_params = params['buttons'] || []
    template_buttons.map.with_index do |button, index|
      {
        type: button['type'],
        text: button['text'],
        url: button['url'] && substitute(button['url'], { '1' => button_params[index]&.dig('parameter') }),
        phone_number: button['phone_number']
      }.compact
    end
  end

  def component(type)
    template['components']&.find { |c| c['type'] == type }
  end

  def substitute(text, values)
    text.gsub(/\{\{\s*(\w+)\s*\}\}/) { values[Regexp.last_match(1)].presence || Regexp.last_match(0) }
  end

  def params
    processed_params || {}
  end
end
