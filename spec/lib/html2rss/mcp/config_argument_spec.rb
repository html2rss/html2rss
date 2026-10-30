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

    it 'rejects a non-Hash config with the designed error instead of a raw TypeError' do
      expect { described_class.parse(config: 'channel: {}') }
        .to raise_error(Html2rss::InvalidOption, 'config must be a Hash, got String')
    end

    it 'accepts a Hash subclass as config' do
      subclass = Class.new(Hash)
      config = subclass[channel: { url: 'https://example.com' }]

      expect(described_class.parse(config:).config).to eq(config_hash)
    end

    it 'names the config context when a key is neither String nor Symbol' do
      expect { described_class.parse(config: { 1 => 'x' }) }
        .to raise_error(ArgumentError, 'config must use string or symbol keys (found 1)')
    end

    it 'rejects a non-String yaml with the designed error instead of a raw parser error' do
      expect { described_class.parse(yaml: 42) }
        .to raise_error(Html2rss::InvalidOption, 'yaml must be a String, got Integer')
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
