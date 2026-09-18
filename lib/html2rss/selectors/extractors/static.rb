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

        # Runtime args for the static extractor.
        Args = Data.define(:static) do
          # @param static [String, nil] fixed value to return
          def initialize(static: nil) = super
        end

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
        # @param args [Args] Args containing the static value.
        # @option args [String, Symbol] :static static value returned by this extractor
        def initialize(_xml, args)
          @args = args
        end

        ##
        # Retrieves and returns the static value.
        #
        # @return [String, Symbol] The static value provided in args.
        def get
          @args.static
        end
      end
    end
  end
end
