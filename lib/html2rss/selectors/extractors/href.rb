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
        # Runtime args for the href extractor.
        Args = Data.define(:selector, :base_url) do
          # @param selector [String, nil] CSS selector for the link element
          # @param base_url [String, Html2rss::Url, nil] page base for relative hrefs
          def initialize(selector: nil, base_url: nil) = super
        end

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
        # @param args [Args]
        # @option args [String] :selector CSS selector used to find the link element
        # @option args [String, Html2rss::Url] :base_url page base URL for relative hrefs
        def initialize(xml, args)
          @args = args
          @element = Extractors.element(xml, args.selector)
          @href = @element.attr('href').to_s
        end

        ##
        # Retrieves and returns the normalized absolute URL.
        #
        # @return [String] The absolute URL.
        def call
          return nil unless @href

          Url.from_relative(@href, @args.base_url)
        end
      end
    end
  end
end
