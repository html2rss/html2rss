# frozen_string_literal: true

module Html2rss
  class Selectors
    module Extractors
      ##
      # Returns a static value provided in the options.
      #
      # Example usage in YAML:
      #
      #    selectors:
      #      author:
      #        extractor: static
      #        static: Foobar
      #
      # Would return:
      #    'Foobar'
      class Static
        # The available option for the static extractor.
        Options = Struct.new('StaticOptions', :static, keyword_init: true)

        ##
        # Initializes the Static extractor.
        #
        # @param _xml [nil, Nokogiri::XML::Element] Unused parameter for compatibility with other extractors.
        # @param options [Options] Options containing the static value.
        def initialize(_xml, options)
          @options = options
        end

        ##
        # Retrieves and returns the static value.
        #
        # @return [String, Symbol] The static value provided in options.
        def get
          @options.static
        end
      end
    end
  end
end
