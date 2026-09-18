# frozen_string_literal: true

module Html2rss
  class Selectors
    module Extractors
      ##
      # Returns the value of the attribute.
      #
      # Imagine this +time+ HTML tag with a +datetime+ attribute:
      #
      #     <time datetime="2019-07-01">...</time>
      #
      # YAML usage example:
      #
      #    selectors:
      #      link:
      #        selector: time
      #        extractor: attribute
      #        attribute: datetime
      #
      # Would return:
      #    '2019-07-01'
      #
      # In case you're extracting a date or a time, consider parsing it
      # during post processing with {PostProcessors::ParseTime}.
      class Attribute
        # Config-facing options contract (validator introspection; +selector+ is runtime-only).
        OPTIONS = [
          OptionSpec.new(name: :attribute, type: String)
        ].freeze

        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = 'Return the value of an HTML attribute on the selected element. ' \
                      'Requires sibling selector option `attribute` (attribute name).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'attribute'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_export = SchemaExport.for_extractor(name: :attribute, klass: self)

        ##
        # Initializes the Attribute extractor.
        #
        # @param xml [Nokogiri::XML::Element]
        # @param attribute [String, nil] attribute name to extract from the selected element
        # @param selector [String, nil] CSS selector used to find the element
        def initialize(xml, attribute: nil, selector: nil, **)
          @attribute = attribute
          @element = Extractors.element(xml, selector)
        end

        ##
        # Retrieves and returns the attribute's value as a string.
        #
        # @return [String] The value of the attribute.
        def call
          @element.attr(@attribute).to_s
        end
      end
    end
  end
end
