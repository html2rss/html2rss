# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Runtime do
  describe '.snapshot' do
    subject(:wire) { described_class.snapshot.to_h }

    it 'publishes gem version, contract version, catalog identity, and botasaurus flag', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- runtime wire is one contract
      expect(wire).to include(
        version: Html2rss::VERSION,
        mcp_contract_version: Html2rss::MCP::Contract::MCP_CONTRACT_VERSION,
        catalog_fingerprint: Html2rss::MCP::Contract.catalog_fingerprint,
        tools: Html2rss::MCP::Contract.catalog_tools,
        botasaurus_configured: false
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
end
