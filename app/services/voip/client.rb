class Voip::Client
  def create_line(phone_number:, webhook_url:, sip: nil, ai_enabled: false)
    body = { phone_number: phone_number, webhook_url: webhook_url, sip: sip, ai: ai_enabled }.compact
    HTTParty.post("#{base_url}/v1/lines", headers: json_headers, body: body.to_json)
  end

  def update_line(line_id, ai_enabled:)
    HTTParty.patch("#{base_url}/v1/lines/#{line_id}", headers: json_headers, body: { ai: ai_enabled }.to_json)
  end

  def delete_line(line_id)
    HTTParty.delete("#{base_url}/v1/lines/#{line_id}", headers: headers)
  end

  def claim_call(call_id, agent_ref:)
    HTTParty.post("#{base_url}/v1/calls/#{call_id}/claim", headers: json_headers, body: { agent_ref: agent_ref.to_s }.to_json)
  end

  def reject_call(call_id)
    HTTParty.post("#{base_url}/v1/calls/#{call_id}/reject", headers: headers)
  end

  def agent_session(agent_ref)
    HTTParty.post("#{base_url}/v1/agents/#{agent_ref}/sessions", headers: headers)
  end

  def recording_url(call_id)
    "#{base_url}/v1/calls/#{call_id}/recording"
  end

  def headers
    { 'Authorization' => "Bearer #{ENV.fetch('VOIP_API_KEY')}" }
  end

  private

  def json_headers
    headers.merge('Content-Type' => 'application/json')
  end

  def base_url
    ENV.fetch('VOIP_API_URL')
  end
end
