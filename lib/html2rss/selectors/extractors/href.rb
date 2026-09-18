# frozen_string_literal: true

module Html2rss
  class Selectors
    module Extractors
      ##
      # Returns the value of the +href+ attribute.
      # It always returns absolute URLs. If the extracted +href+ value is a
      # relative URL, it prepends the page base URL.
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
        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = 'Return the absolute URL from the selected element\'s `href` attribute ' \
                      '(relative hrefs are resolved against the page base URL).'

        # Example extractor name values for JSON Schema +examples+.
        EXAMPLES = [
          'href'
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this extractor name
        def self.schema_export = SchemaExport.for_extractor(name: :href, klass: self)

        ##
        # Initializes the Href extractor.
        #
        # @param xml [Nokogiri::XML::Element]
        # @param base_url [String, Html2rss::Url, nil] page base URL for relative hrefs
        # @param selector [String, nil] CSS selector used to find the link element
        def initialize(xml, base_url: nil, selector: nil, **)
          @base_url = base_url
          @element = Extractors.element(xml, selector)
          @href = @element.attr('href').to_s
        end

        ##
        # Retrieves and returns the normalized absolute URL.
        #
        # @return [Html2rss::Url, nil] The absolute URL.
        def call
          return nil unless @href

          Url.from_relative(@href, @base_url)
        end
      end
    end
  end
end
