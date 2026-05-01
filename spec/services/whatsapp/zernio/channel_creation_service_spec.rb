require 'rails_helper'

describe Whatsapp::Zernio::ChannelCreationService do
  let(:account) { create(:account) }
  let(:base_params) do
    {
      account: account,
      phone_number: '+5511999999999',
      account_id: 'zacct_1',
      profile_id: 'zprof_1',
      inbox_name: 'Vendas WhatsApp'
    }
  end

  before do
    # Bypass network/validation hooks during channel creation in specs
    allow_any_instance_of(Channel::Whatsapp).to receive(:validate_provider_config).and_return(true)
    allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates).and_return(nil)
  end

  describe '#perform on create' do
    it 'creates a Channel::Whatsapp with provider=whatsapp_cloud and gateway=zernio' do
      channel = described_class.new(**base_params).perform

      expect(channel.provider).to eq('whatsapp_cloud')
      expect(channel.provider_config).to include(
        'gateway' => 'zernio',
        'account_id' => 'zacct_1',
        'profile_id' => 'zprof_1',
        'source' => 'embedded_signup'
      )
      expect(channel.phone_number).to eq('+5511999999999')
      expect(channel.inbox.name).to eq('Vendas WhatsApp')
    end

    it 'raises when phone_number is already taken' do
      create(:channel_whatsapp, account: account, phone_number: '+5511999999999',
                                validate_provider_config: false, sync_templates: false)
      expect { described_class.new(**base_params).perform }.to raise_error(RuntimeError)
    end
  end

  describe '#perform on reauth (inbox_id given)' do
    let!(:existing_channel) do
      create(:channel_whatsapp, account: account, phone_number: '+551100000000',
                                provider: 'whatsapp_cloud',
                                provider_config: { 'gateway' => 'zernio', 'account_id' => 'old' },
                                validate_provider_config: false, sync_templates: false)
    end

    it 'updates the existing channel without creating a new inbox' do
      original_inbox_id = existing_channel.inbox.id

      expect do
        described_class.new(**base_params, inbox_id: existing_channel.inbox.id).perform
      end.not_to change(Inbox, :count)

      existing_channel.reload
      expect(existing_channel.phone_number).to eq('+5511999999999')
      expect(existing_channel.provider_config['account_id']).to eq('zacct_1')
      expect(existing_channel.provider_config['gateway']).to eq('zernio')
      expect(existing_channel.inbox.id).to eq(original_inbox_id)
    end
  end
end
