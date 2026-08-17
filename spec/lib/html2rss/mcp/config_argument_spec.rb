# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::ConfigArgument do
  describe '.parse' do
    let(:config_hash) { { channel: { url: 'https://example.com' } } }

    it 'accepts a config hash and symbolizes keys' do
      argument = described_class.parse(config: { 'channel' => { 'url' => 'https://example.com' } })

      expect(argument.config).to eq(config_hash)
    end

    it 'accepts yaml through Config.from_yaml so MCP does not own YAML' do
      yaml = Html2rss::Config.to_yaml(config_hash)

      expect(described_class.parse(yaml:).config).to eq(config_hash)
    end

    it 'rejects both config and yaml so the XOR cannot be smuggled past' do
      expect { described_class.parse(config: config_hash, yaml: 'channel: {}') }
        .to raise_error(ArgumentError, /exactly one of config or yaml/)
    end

    it 'rejects neither config nor yaml' do
      expect { described_class.parse }.to raise_error(ArgumentError, /exactly one of config or yaml/)
    end

    it 'treats blank yaml as absent so XOR stays honest' do
      expect { described_class.parse(yaml: "  \n") }
        .to raise_error(ArgumentError, /exactly one of config or yaml/)
    end

    it 'rejects local_file so apply and validate share the Contract gate' do
      expect do
        described_class.parse(config: config_hash.merge(strategy: :local_file,
                                                        request: { local_file_path: '/tmp/page.html' }))
      end.to raise_error(Html2rss::MCP::Contract::UnpublishedRequestError)
    end
  end
end
