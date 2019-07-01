module Html2rss
  module ItemExtractors
    class Text
      ##
      # Return the text of the attribute. This is the default extractor used,
      # when no extractor is explicitly given.
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
      #        extractor: text
      #
      # Would return:
      #    'Lorem ipsum dolor ...'
      def initialize(xml, options)
        @element = ItemExtractors.element(xml, options)
      end

      def get
        @element&.text&.strip&.split&.join(' ')
      end
    end
  end
end
