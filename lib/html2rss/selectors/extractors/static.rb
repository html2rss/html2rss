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
      #      byline:
      #        extractor: static
      #        static: Foobar
      #
      # Would return:
      #    'Foobar'
      class Static
        # Config-facing option types (excluding shared selector fields supplied at runtime).
        OPTION_TYPES = { static: String }.freeze

        # The available option for the static extractor.
        Options = Struct.new('StaticOptions', :static, keyword_init: true)

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Return a fixed value from sibling selector option `static` (no DOM read).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'static'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_doc = SchemaDoc.for_extractor(name: :static, klass: self)

        ##
        # Initializes the Static extractor.
        #
        # @param _xml [nil, Nokogiri::XML::Element] Unused parameter for compatibility with other extractors.
        # @param options [Options] Options containing the static value.
        # @option options [String, Symbol] :static static value returned by this extractor
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
