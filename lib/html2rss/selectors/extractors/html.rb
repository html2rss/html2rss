# frozen_string_literal: true

module Html2rss
  class Selectors
    module Extractors
      ##
      # Returns the HTML content of the specified element.
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
      #        extractor: html
      #
      # Would return:
      #    '<p>Lorem <b>ipsum</b> dolor ...</p>'
      #
      # Always ensure to sanitize the HTML during post-processing with
      # {PostProcessors::SanitizeHtml}.
      class Html
        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = 'Return the outer HTML of the selected element. ' \
                      'Sanitize during post-processing (e.g. `sanitize_html`).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'html'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_export = SchemaExport.for_extractor(name: :html, klass: self)

        ##
        # Initializes the Html extractor.
        #
        # @param xml [Nokogiri::XML::Element]
        # @param selector [String, nil] CSS selector used to find the element
        def initialize(xml, selector: nil, **)
          @element = Extractors.element(xml, selector)
        end

        ##
        # Retrieves and returns the HTML content of the element.
        #
        # @return [String] The HTML content.
        def call
          @element.to_s
        end
      end
    end
  end
end
