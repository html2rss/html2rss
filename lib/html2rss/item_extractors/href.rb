# frozen_string_literal: true

module Html2rss
  module ItemExtractors
    ##
    # Returns the value of the +href+ attribute.
    # It always returns absolute URLs. If the extracted +href+ value is a
    # relative URL, it prepends the channel's URL.
    #
    # Imagine this +a+ HTML element with a +href+ attribute:
    #
    #     <a href="/posts/latest-findings">...</a>
    #
    # YAML usage example:
    #    channel:
    #      url: http://blog-without-a-feed.example.com
    #      ...
    #    selectors:
    #      link:
    #        selector: a
    #        extractor: href
    #
    # Would return:
    #    'http://blog-without-a-feed.example.com/posts/latest-findings'
    class Href
      # The available options for the href (attribute) extractor.
      Options = Struct.new('HrefOptions', :selector, :channel, keyword_init: true)

      ##
      # Initializes the Href extractor.
      #
      # @param xml [Nokogiri::XML::Element]
      # @param options [Options]
      def initialize(xml, options)
        @options = options
        @element = ItemExtractors.element(xml, options.selector)
        @href = @element.attr('href').to_s
      end

      ##
      # Retrieves and returns the normalized absolute URL.
      #
      # @return [String] The absolute URL.
      def get
        return nil unless @href

        sanitized_href = Html2rss::Utils.sanitize_url(@href)
        Html2rss::Utils.build_absolute_url_from_relative(sanitized_href, @options.channel.url)
      end
    end
  end
end
