# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Runtime facts for the MCP process (env configuration, wire coercion).
    module Runtime
      # Published +html2rss://runtime+ resource (never leaks secrets).
      Snapshot = Data.define(
        :version,
        :mcp_contract_version,
        :catalog_fingerprint,
        :tools,
        :botasaurus_configured
      )

      module_function

      ##
      # @return [Boolean] whether Botasaurus transport is configured in this process
      def botasaurus_configured?
        !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
      end

      ##
      # @return [Snapshot] runtime capabilities and catalog identity for MCP clients
      def snapshot
        Snapshot.new(
          version: Html2rss::VERSION,
          mcp_contract_version: Contract::MCP_CONTRACT_VERSION,
          catalog_fingerprint: Contract.catalog_fingerprint,
          tools: Contract.catalog_tools,
          botasaurus_configured: botasaurus_configured?
        )
      end

      ##
      # @param strategy [String, Symbol, nil]
      # @return [Symbol]
      def coerce_strategy(strategy)
        (strategy || :auto).to_sym
      end
    end
  end
end
