require 'rails_helper'

describe Whatsapp::Providers::ZernioService do
  let(:account) { create(:account) }
  let(:zernio_conversation_id) { 'zconv_123' }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           provider_config: { 'gateway' => 'zernio', 'account_id' => 'zacct_1', 'profile_id' => 'zprof' },
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:conversation) do
    conv = create(:conversation, account: account, inbox: channel.inbox)
    conv.update!(additional_attributes: { 'zernio_conversation_id' => zernio_conversation_id })
    conv
  end
  let(:message) { create(:message, conversation: conversation, account: account, content: 'oi') }
  let(:service) { described_class.new(whatsapp_channel: channel) }

  before do
    stub_const('ENV', ENV.to_h.merge('ZERNIO_API_KEY' => 'zkey', 'ZERNIO_BASE_URL' => 'https://api.zernio.com'))
  end

  describe '#send_message' do
    context 'when zernio_conversation_id is present' do
      it 'POSTs text body to inbox conversation messages endpoint' do
        stubbed = stub_request(:post, "https://api.zernio.com/v1/inbox/conversations/#{zernio_conversation_id}/messages")
                  .with(
                    body: hash_including(accountId: 'zacct_1', message: 'oi'),
                    headers: { 'Authorization' => 'Bearer zkey' }
                  )
                  .to_return(
                    status: 200,
                    body: {
                      success: true,
                      data: { messageId: 'zmsg_1', conversationId: zernio_conversation_id }
                    }.to_json,
                    headers: { 'Content-Type' => 'application/json' }
                  )

        result = service.send_message('+551199999', message)

        expect(stubbed).to have_been_requested
        expect(result).to eq('zmsg_1')
      end
    end

    context 'when zernio_conversation_id is missing' do
      let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }

      it 'fails the message and does not call the API' do
        expect { service.send_message('+551199999', message) }
          .to change { message.reload.status }.to('failed')
      end
    end
  end

  describe '#send_template' do
    let(:template_info) { { name: 'hello', lang_code: 'pt_BR', parameters: [{ type: 'body', parameters: [{ type: 'text', text: 'oi' }] }] } }

    it 'POSTs to the conversation messages endpoint with accountId and template' do
      stubbed = stub_request(:post, "https://api.zernio.com/v1/inbox/conversations/#{zernio_conversation_id}/messages")
                .with(body: hash_including(
                  'accountId' => 'zacct_1',
                  'template' => hash_including(
                    'elements' => [hash_including('name' => 'hello', 'language' => 'pt_BR')]
                  )
                ))
                .to_return(
                  status: 200,
                  body: {
                    success: true,
                    data: { messageId: 'zmsg_t', conversationId: zernio_conversation_id }
                  }.to_json,
                  headers: { 'Content-Type' => 'application/json' }
                )

      result = service.send_template('+551199999', template_info, message)

      expect(stubbed).to have_been_requested
      expect(result).to eq('zmsg_t')
    end

    it 'fails the message when zernio_conversation_id is missing' do
      conv = create(:conversation, account: account, inbox: channel.inbox)
      msg = create(:message, conversation: conv, account: account)

      expect { service.send_template('+551199999', template_info, msg) }
        .to change { msg.reload.status }.to('failed')
    end
  end

  describe '.update_profile' do
    it 'PATCHes /v1/profiles/:id with the new name' do
      stubbed = stub_request(:patch, 'https://api.zernio.com/v1/profiles/zprof')
                .with(
                  body: { name: 'Acme -> WhatsApp (+5511999)' }.to_json,
                  headers: { 'Authorization' => 'Bearer zkey' }
                )
                .to_return(status: 200, body: { profile: { _id: 'zprof', name: 'Acme -> WhatsApp (+5511999)' } }.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      described_class.update_profile(id: 'zprof', name: 'Acme -> WhatsApp (+5511999)')

      expect(stubbed).to have_been_requested
    end

    it 'raises when Zernio returns an error' do
      stub_request(:patch, 'https://api.zernio.com/v1/profiles/zprof').to_return(status: 500)

      expect { described_class.update_profile(id: 'zprof', name: 'x') }
        .to raise_error(/Zernio profile update failed/)
    end
  end

  describe '#api_headers' do
    it 'uses the global ZERNIO_API_KEY' do
      expect(service.api_headers).to eq('Authorization' => 'Bearer zkey', 'Content-Type' => 'application/json')
    end
  end

  describe '.request_options' do
    it 'adds Zernio proxy options outside production when configured' do
      stub_const('ENV', ENV.to_h.merge('PROXY_URL' => 'http://user:pass@127.0.0.1:8080'))
      allow(Rails.env).to receive(:production?).and_return(false)

      expect(described_class.request_options(headers: { 'Authorization' => 'Bearer zkey' })).to include(
        headers: { 'Authorization' => 'Bearer zkey' },
        http_proxyaddr: '127.0.0.1',
        http_proxyport: 8080,
        http_proxyuser: 'user',
        http_proxypass: 'pass',
        verify: false
      )
    end

    it 'does not use PROXY_URL in production' do
      stub_const('ENV', ENV.to_h.merge('PROXY_URL' => 'http://127.0.0.1:8080'))
      allow(Rails.env).to receive(:production?).and_return(true)

      expect(described_class.request_options(headers: { 'Authorization' => 'Bearer zkey' })).to eq(
        headers: { 'Authorization' => 'Bearer zkey' }
      )
    end
  end

  describe '#process_response' do
    it 'persists conversationId on Conversation and Message additional_attributes' do
      response = instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'success' => true,
          'data' => { 'messageId' => 'm1', 'conversationId' => 'newconv' }
        }
      )
      conversation.update!(additional_attributes: {})

      result = service.process_response(response, message)

      expect(result).to eq('m1')
      expect(conversation.reload.additional_attributes['zernio_conversation_id']).to eq('newconv')
      expect(message.reload.additional_attributes['zernio_conversation_id']).to eq('newconv')
    end
  end
end
