# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Runtime facts for the MCP process (env configuration, wire coercion).
    module Runtime
      module_function

      ##
      # @return [Boolean] whether Botasaurus transport is configured in this process
      def botasaurus_configured?
        !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
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
