# frozen_string_literal: true

module Html2rss
  module ItemExtractors
    ##
    # Returns the current Time.
    #
    # YAML usage example:
    #
    #    selectors:
    #      updated:
    #        extractor: current_time
    class CurrentTime
      REQUIRED_OPTIONS = [].freeze

      ##
      # @param _xml [nil, String]
      # @param _options [nil, Struct::CurrentTimeOptions]
      def initialize(_xml, _options); end

      ##
      # @return [Time]
      def get
        Time.new
      end
    end
  end
end
