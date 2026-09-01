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
end
