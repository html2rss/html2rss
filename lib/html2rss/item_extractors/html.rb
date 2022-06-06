# frozen_string_literal: true

module Html2rss
  module ItemExtractors
    ##
    # Return the HTML of the attribute.
    #
    # Imagine this HTML structure:
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
    # Always make sure to sanitize the HTML during post processing with
    # {AttributePostProcessors::SanitizeHtml}.
    class Html
      Options = Struct.new('HtmlOptions', :selector, keyword_init: true)

      ##
      # @param xml [Nokogiri::XML::Element]
      # @param options [Options]
      def initialize(xml, options)
        @element = ItemExtractors.element(xml, options.selector)
      end

      ##
      # @return [String]
      def get
        @element.to_s
      end
    end
  end
end
