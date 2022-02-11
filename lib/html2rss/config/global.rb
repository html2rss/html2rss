module Html2rss
  class Config
    ##
    # Holds the configuration for all Html2rss options.
    class Global
      def initialize(global_config = {})
        @global_config = global_config
      end

      ##
      # @return [Hash]
      def headers
        @global_config.fetch(:headers, {})
      end

      ##
      # @return [Array<Hash>]
      def stylesheets
        @global_config.fetch(:stylesheets, [])
      end
    end
  end
end
