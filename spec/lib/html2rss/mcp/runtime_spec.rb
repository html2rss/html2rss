# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

RSpec.describe Html2rss::MCP::Runtime do
  describe '.snapshot' do
    subject(:wire) { described_class.snapshot.to_h }

    it 'publishes gem version, contract version, catalog identity, and botasaurus flag', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- runtime wire is one contract
      expect(wire).to include(
        version: Html2rss::VERSION,
        mcp_contract_version: Html2rss::MCP::Contract::MCP_CONTRACT_VERSION,
        catalog_fingerprint: Html2rss::MCP::Contract.catalog_fingerprint,
        tools: Html2rss::MCP::Contract.catalog_tools,
        botasaurus_configured: false,
        response_cache_ttl: nil
      )
    end

    it 'returns a typed Snapshot' do
      expect(described_class.snapshot).to be_a(described_class::Snapshot)
    end
  end

  describe '.botasaurus_configured?' do
    before { allow(ENV).to receive(:[]).and_call_original }

    it 'is true when BOTASAURUS_SCRAPER_URL carries a value' do
      allow(ENV).to receive(:[]).with('BOTASAURUS_SCRAPER_URL').and_return('http://localhost:3000')

      expect(described_class.botasaurus_configured?).to be(true)
    end

    it 'is false when BOTASAURUS_SCRAPER_URL is unset' do
      allow(ENV).to receive(:[]).with('BOTASAURUS_SCRAPER_URL').and_return(nil)

      expect(described_class.botasaurus_configured?).to be(false)
    end

    it 'is false when BOTASAURUS_SCRAPER_URL is blank after stripping whitespace' do
      allow(ENV).to receive(:[]).with('BOTASAURUS_SCRAPER_URL').and_return("  \t ")

      expect(described_class.botasaurus_configured?).to be(false)
    end
  end

  describe '.install_response_cache!' do
    after { Html2rss::RequestService.response_cache = nil }

    {
      nil => 300, '' => 300, ' 120 ' => 120, '1' => 1,
      '0' => nil, ' off ' => nil, 'off' => nil, 'OFF' => nil, 'false' => nil,
      '010' => 10, '0x10' => 300, 'abc' => 300, '-5' => 300, '1.5' => 300
    }.each do |value, expected|
      it "installs ttl #{expected.inspect} for HTML2RSS_RESPONSE_CACHE_TTL=#{value.inspect}" do
        ClimateControl.modify(HTML2RSS_RESPONSE_CACHE_TTL: value) do
          described_class.install_response_cache!

          expect(Html2rss::RequestService.response_cache&.ttl).to eq(expected)
        end
      end
    end

    it 'stays silent when the variable is unset or blank', :aggregate_failures do
      allow(Html2rss::Log).to receive(:warn)
      [nil, '  '].each do |value|
        ClimateControl.modify(HTML2RSS_RESPONSE_CACHE_TTL: value) { described_class.install_response_cache! }
      end

      expect(Html2rss::Log).not_to have_received(:warn)
    end

    it 'warns and falls back to the default for an unusable value', :aggregate_failures do
      allow(Html2rss::Log).to receive(:warn)
      ClimateControl.modify(HTML2RSS_RESPONSE_CACHE_TTL: 'abc') { described_class.install_response_cache! }

      expect(Html2rss::Log).to have_received(:warn).with(/"abc" is not a positive integer; using 300s/)
    end

    it 'publishes the installed ttl in the snapshot' do
      Html2rss::RequestService.response_cache = Html2rss::RequestService::ResponseCache.new(ttl: 42)

      expect(described_class.snapshot.response_cache_ttl).to eq(42)
    end
  end
end
