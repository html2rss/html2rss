module Html2rss
  module ItemExtractors
    ##
    # Returns the value of the attribute.
    #
    # Imagine this +time+ HTML element with a +datetime+ attribute:
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
    # In case you're extracting a date or a time, do not forget to parse it
    # during post processing with
    # {AttributePostProcessors::ParseTime}[rdoc-ref:Html2rss::AttributePostProcessors::ParseTime].
    class Attribute
      def initialize(xml, options)
        @options = options
        @element = ItemExtractors.element(xml, options)
      end

      ##
      # @return [String]
      def get
        @element.attr(@options['attribute']).to_s
      end
    end
  end
end
