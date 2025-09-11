# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Builds a sanitized article description from the base text, title, and optional media.
    #
    # Combines media elements (images, audio, video, PDFs) with sanitized text content
    # to create rich RSS descriptions that reveal more scraped information.
    #
    # @example Basic usage
    #   builder = DescriptionBuilder.new(
    #     base: "Article content",
    #     title: "Article Title",
    #     url: "https://example.com",
    #     enclosures: [enclosure_object],
    #     image: "https://example.com/image.jpg"
    #   )
    #   description = builder.call
    #
    class DescriptionBuilder
      # @param base [String] The base text content for the description
      # @param title [String] The article title (used for alt text and title removal)
      # @param url [String, Html2rss::Url] The article URL (used for sanitization)
      # @param enclosures [Array<Html2rss::RssBuilder::Enclosure>, nil] Media enclosures
      # @param image [String, Html2rss::Url, nil] Fallback image URL
      def initialize(base:, title:, url:, enclosures:, image:)
        @base = base.to_s
        @title = title
        @url = url
        @enclosures = Array(enclosures)
        @image = image
      end

      # Generates the complete description with media and sanitized text.
      #
      # @return [String, nil] The complete description or nil if empty
      def call
        fragments = []
        fragments.concat(Array(rendered_media))
        fragments << processed_base_description
        fragments << media_table_html

        result = fragments.compact.join("\n\n").strip
        result.empty? ? nil : result
      end

      private

      def rendered_media
        return render_enclosures if @enclosures.any?
        return render_fallback_image if @image

        []
      end

      def render_enclosures
        @enclosures.filter_map do |enclosure|
          MediaRenderer.for(enclosure:, image: @image, title: @title)&.to_html
        end
      end

      def render_fallback_image
        [MediaRenderer.for(enclosure: nil, image: @image, title: @title)&.to_html]
      end

      def media_table_html
        MediaTableRenderer.new(enclosures: @enclosures, image: @image).to_html
      end

      def processed_base_description
        text = RssBuilder::Article.remove_pattern_from_start(@base, @title)
        Html2rss::Selectors::PostProcessors::SanitizeHtml.get(text, @url)
      end
    end
  end
end
