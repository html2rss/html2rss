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
      ##
      # @param xml [Nokogiri::XML::Element]
      # @param options [Hash<Symbol, Object>]
      def initialize(xml, options)
        @options = options
        element = ItemExtractors.element(xml, options)
        @href = Html2rss::Utils.sanitize_url(element.attr('href'))
      end

      # @return [URI::HTTPS, URI::HTTP]
      def get
        Html2rss::Utils.build_absolute_url_from_relative(@href, @options[:channel][:url])
      end
    end
  end
end
