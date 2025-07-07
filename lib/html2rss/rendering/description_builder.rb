# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Builds a sanitized article description from the base text, title, and optional media.
    class DescriptionBuilder
      def initialize(base:, title:, url:, enclosure:, image:)
        @base = base.to_s
        @title = title
        @url = url
        @enclosure = enclosure
        @image = image
      end

      def call
        fragments = []
        fragments << media_renderer&.to_html
        fragments << processed_base_description

        result = fragments.compact.join("\n").strip
        result.empty? ? nil : result
      end

      private

      def media_renderer
        MediaRenderer.for(enclosure: @enclosure, image: @image, title: @title)
      end

      def processed_base_description
        text = RssBuilder::Article.remove_pattern_from_start(@base, @title)
        Html2rss::Selectors::PostProcessors::SanitizeHtml.get(text, @url)
      end
    end
  end
end
