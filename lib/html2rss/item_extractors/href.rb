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
      def initialize(xml, options)
        @options = options
        element = ItemExtractors.element(xml, options)
        @href = element.attr('href').to_s
      end

      # @return [URI::HTTPS, URI::HTTP]
      def get
        href.start_with?('http') ? absolute_url : build_absolute_url_from_relative
      end

      private

      def absolute_url
        URI(href)
      end

      def build_absolute_url_from_relative
        path, query = href.split('?')

        URI(@options['channel']['url']).tap do |uri|
          uri.path = path.to_s.start_with?('/') ? path : "/#{path}"
          uri.query = query
        end
      end

      attr_reader :href
    end
  end
end
