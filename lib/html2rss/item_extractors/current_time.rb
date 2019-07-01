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
      def initialize(_xml, _options); end

      def get
        Time.new
      end
    end
  end
end
