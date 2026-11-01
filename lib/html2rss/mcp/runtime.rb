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

      class << self
        ##
        # @return [Boolean] whether Botasaurus transport is configured in this process
        def botasaurus_configured?
          !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
        end

        ##
        # Opts the long-lived MCP process in to reusing initial page fetches, so an agent iterating
        # +inspect -> capture -> validate -> test+ on one URL fetches it once per TTL window.
        #
        # Configured by +HTML2RSS_RESPONSE_CACHE_TTL+ seconds; unset leaves caching off.
        #
        # @return [void]
        def install_response_cache!
          ttl = ENV['HTML2RSS_RESPONSE_CACHE_TTL'].to_s.strip
          return if ttl.empty?

          RequestService.response_cache = RequestService::ResponseCache.new(ttl: Integer(ttl))
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
      end
    end
  end
end
