# frozen_string_literal: true

module Html2rss
  module Syndication
    ##
    # Scans raw HTML for +<link rel="alternate">+ hints that point at RSS/Atom feeds.
    module AlternateLinks
      LINK_TAG_RE = /<link\b[^>]*>/i
      HREF_RE = /\bhref\s*=\s*["']([^"']+)["']/i
      TYPE_RE = /\btype\s*=\s*["']([^"']+)["']/i
      REL_RE = /\brel\s*=\s*["']([^"']+)["']/i
      private_constant :LINK_TAG_RE, :HREF_RE, :TYPE_RE, :REL_RE

      class << self
        ##
        # @param html [String] raw HTML
        # @return [Array<String>] hrefs of alternate links that look like feeds
        def hrefs(html)
          html.scan(LINK_TAG_RE).filter_map { |tag| feed_href(tag) }
        end

        private

        def feed_href(tag)
          return unless tag[REL_RE, 1].to_s.downcase.split(/\s+/).include?('alternate')

          href = tag[HREF_RE, 1]
          return if href.nil? || href.empty?

          href.strip if syndication_type?(tag[TYPE_RE, 1]) || href.match?(/rss|atom|feed|\.xml/i)
        end

        def syndication_type?(type)
          type.to_s.downcase.match?(/rss|atom/)
        end
      end
    end
  end
end
