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
        :botasaurus_configured,
        :response_cache_ttl
      )

      # Seconds an initial page fetch is reused when +HTML2RSS_RESPONSE_CACHE_TTL+ is unset.
      DEFAULT_RESPONSE_CACHE_TTL = 300
      # Values of +HTML2RSS_RESPONSE_CACHE_TTL+ that disable the cache.
      CACHE_OFF_VALUES = %w[0 off false].freeze
      private_constant :CACHE_OFF_VALUES

      class << self
        ##
        # @return [Boolean] whether Botasaurus transport is configured in this process
        def botasaurus_configured?
          !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
        end

        ##
        # Installs the initial-fetch cache for the long-lived MCP process, so an agent iterating
        # +inspect -> capture -> validate -> test+ on one URL fetches it once per TTL window.
        # +HTML2RSS_RESPONSE_CACHE_TTL+ sets the seconds ({DEFAULT_RESPONSE_CACHE_TTL} when unset);
        # +0+, +off+ or +false+ disables caching. An unusable value logs a warning and uses the default.
        #
        # @return [void]
        def install_response_cache!
          ttl = response_cache_ttl
          RequestService.response_cache = ttl && RequestService::ResponseCache.new(ttl:)
        end

        ##
        # @return [Snapshot] runtime capabilities and catalog identity for MCP clients
        def snapshot
          Snapshot.new(
            version: Html2rss::VERSION,
            mcp_contract_version: Contract::MCP_CONTRACT_VERSION,
            catalog_fingerprint: Contract.catalog_fingerprint,
            tools: Contract.catalog_tools,
            botasaurus_configured: botasaurus_configured?,
            response_cache_ttl: RequestService.response_cache&.ttl
          )
        end

        private

        def response_cache_ttl
          raw = ENV['HTML2RSS_RESPONSE_CACHE_TTL'].to_s.strip.downcase
          return DEFAULT_RESPONSE_CACHE_TTL if raw.empty?
          return if CACHE_OFF_VALUES.include?(raw)

          ttl = Integer(raw, 10, exception: false)
          ttl&.positive? ? ttl : invalid_cache_ttl(raw)
        end

        def invalid_cache_ttl(raw)
          Log.warn("HTML2RSS_RESPONSE_CACHE_TTL=#{raw.inspect} is not a positive integer; " \
                   "using #{DEFAULT_RESPONSE_CACHE_TTL}s")
          DEFAULT_RESPONSE_CACHE_TTL
        end
      end
    end
  end
end
