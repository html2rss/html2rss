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
    # {AttributePostProcessors::SanitizeHtml}[rdoc-ref:Html2rss::AttributePostProcessors::SanitizeHtml].
    class Html
      def initialize(xml, options)
        @element = ItemExtractors.element(xml, options)
      end

      def get
        @element&.to_s
      end
    end
  end
end
