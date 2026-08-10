# frozen_string_literal: true

module Html2rss
  class AutoSource
    class LinkHeuristics
      # Extracts a normalized href from a Nokogiri anchor or raw href value.
      class HrefExtractor
        # Regexp to capture everything before the first '#'
        HREF_BASE_PATTERN = /\A([^#]*)/

        # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
        # @return [String, nil] href without fragment, or nil when blank
        def self.call(anchor_or_href) = new(anchor_or_href).call

        # @param anchor_or_href [Nokogiri::XML::Element, String, #to_s] anchor element or href-like value
        def initialize(anchor_or_href)
          @anchor_or_href = anchor_or_href
        end

        # @return [String, nil] href without fragment, or nil when blank
        def call
          href = case @anchor_or_href
                 when Nokogiri::XML::Node
                   @anchor_or_href['href']
                 else
                   @anchor_or_href
                 end

          return unless href

          # Extract base part before # and strip whitespace
          base = href.to_s[HREF_BASE_PATTERN, 1].strip
          base unless base.empty?
        end
      end
    end
  end
end
