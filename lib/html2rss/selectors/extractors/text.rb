# frozen_string_literal: true

module Html2rss
  class Selectors
    module Extractors
      ##
      # Return the text content of the attribute. This is the default extractor used,
      # when no extractor is explicitly given.
      #
      # Example HTML structure:
      #
      #     <p>Lorem <b>ipsum</b> dolor ...</p>
      #
      # YAML usage example:
      #
      #    selectors:
      #      description:
      #        selector: p
      #        extractor: text
      #
      # Would return:
      #    'Lorem ipsum dolor ...'
      class Text
        # The available options for the text extractor.
        Options = Struct.new('TextOptions', :selector, keyword_init: true)

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Return collapsed visible text of the selected element (default extractor).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'text'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_doc = SchemaDoc.for_extractor(name: :text, klass: self)

        ##
        # Initializes the Text extractor.
        #
        # @param xml [Nokogiri::XML::Element]
        # @param options [Options]
        # @option options [String] :selector CSS selector used to find the element
        def initialize(xml, options)
          @element = Extractors.element(xml, options.selector)
        end

        ##
        # Retrieves and returns the text content of the element.
        #
        # @return [String] The text content.
        def get
          @element.text.to_s.strip.gsub(/\s+/, ' ')
        end
      end
    end
  end
end
