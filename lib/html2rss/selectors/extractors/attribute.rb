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
          Option.new(name: :attribute, type: String)
        ].freeze

        # Runtime options for the attribute extractor.
        Options = Data.define(:selector, :attribute) do
          # @param selector [String, nil] CSS selector for the element
          # @param attribute [String, nil] HTML attribute name to read
          def initialize(selector: nil, attribute: nil) = super
        end

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Return the value of an HTML attribute on the selected element. ' \
                      'Requires sibling selector option `attribute` (attribute name).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'attribute'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_doc = SchemaDoc.for_extractor(name: :attribute, klass: self)

        ##
        # Initializes the Attribute extractor.
        #
        # @param xml [Nokogiri::XML::Element]
        # @param options [Options]
        # @option options [String] :selector CSS selector used to find the element
        # @option options [String] :attribute attribute name to extract from the selected element
        def initialize(xml, options)
          @options = options
          @element = Extractors.element(xml, options.selector)
        end

        ##
        # Retrieves and returns the attribute's value as a string.
        #
        # @return [String] The value of the attribute.
        def get
          @element.attr(@options.attribute).to_s
        end
      end
    end
  end
end
