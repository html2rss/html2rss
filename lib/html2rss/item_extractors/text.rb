# frozen_string_literal: true

module Html2rss
  module ItemExtractors
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
    class Text
      Options = Struct.new('TextOptions', :selector, keyword_init: true)

      ##
      # @param xml [Nokogiri::XML::Element]
      # @param options [Options]
      def initialize(xml, options)
        @options = options
        @element = ItemExtractors.element(xml, options.selector)
      end

      ##
      # @return [String]
      def get
        @element.text.to_s.strip.split.join(' ')
      end
    end
  end
end
