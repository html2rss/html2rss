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
        # Config-facing options contract (validator introspection).
        OPTIONS = [
          OptionSpec.new(name: :static, type: String)
        ].freeze

        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = 'Return a fixed value from sibling selector option `static` (no DOM read).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'static'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_export = SchemaExport.for_extractor(name: :static, klass: self)

        ##
        # Initializes the Static extractor.
        #
        # @param _xml [nil, Nokogiri::XML::Element] Unused parameter for compatibility with other extractors.
        # @param static [String, Symbol, nil] static value returned by this extractor
        def initialize(_xml = nil, static: nil, **)
          @static = static
        end

        ##
        # Retrieves and returns the static value.
        #
        # @return [String, Symbol, nil] The static value.
        def call
          @static
        end
      end
    end
  end
end
