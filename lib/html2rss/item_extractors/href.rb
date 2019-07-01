module Html2rss
  module ItemExtractors
    ##
    # Returns the value of the +href+ attribute.
    # It always returns absolute URLs. If the extracted +href+ value is a
    # relative URL, it prepends the channel's URL.
    #
    # Imagine this +a+ HTML element with the +href+ attribute:
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
        @element = ItemExtractors.element(xml, options)
      end

      def get
        href = @element.attr('href').to_s
        path, query = href.split('?')

        if href.start_with?('http')
          uri = URI(href)
        else
          uri = URI(@options['channel']['url'])
          uri.path = path.to_s.start_with?('/') ? path : "/#{path}"
          uri.query = query
        end

        uri
      end
    end
  end
end
