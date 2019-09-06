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
        uri.absolute? ? uri : build_absolute_url_from_relative
      end

      def self.build_absolute_url_from_relative(url, channel_url)
        path, query = url.split('?')

        URI(channel_url).tap do |uri|
          uri.path = path.to_s.start_with?('/') ? path : "/#{path}"
          uri.query = query
        end
      end

      private

      def uri
        URI(href)
      end

      def build_absolute_url_from_relative
        self.class.build_absolute_url_from_relative(href, @options['channel']['url'])
      end

      attr_reader :href
    end
  end
end
