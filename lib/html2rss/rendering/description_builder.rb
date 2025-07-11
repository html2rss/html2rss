# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Builds a sanitized article description from the base text, title, and optional media.
    class DescriptionBuilder
      def initialize(base:, title:, url:, enclosures:, image:)
        @base = base.to_s
        @title = title
        @url = url
        @enclosures = enclosures || []
        @image = image
      end

      def call
        fragments = Array(rendered_media)
        fragments << processed_base_description

        result = fragments.compact.join("\n").strip
        result.empty? ? nil : result
      end

      private

      def rendered_media
        @enclosures.filter_map do |enclosure|
          MediaRenderer.for(enclosure:, image: @image, title: @title)&.to_html
        end
      end

      def processed_base_description
        text = RssBuilder::Article.remove_pattern_from_start(@base, @title)
        Html2rss::Selectors::PostProcessors::SanitizeHtml.get(text, @url)
      end
    end
  end
end
