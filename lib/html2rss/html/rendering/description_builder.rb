# frozen_string_literal: true

module Html2rss
  module Html
    module Rendering
      # Builds a sanitized article description from the base text, title, and at most one media element.
      #
      # The media element is the item's RSS enclosure when it is an audio or video file (a player), else the item
      # image; a downloadable document (PDF, ZIP) falls back to the image. Nothing is rendered when the sanitized
      # description already references that file: an +src+, +href+ or +srcset+ URL resolving to the same normalized
      # absolute URL. Those attributes are parsed only when the description contains the file name (+File.basename+
      # of its path).
      #
      # @example Basic usage
      #   builder = DescriptionBuilder.new(
      #     base: "Article content",
      #     title: "Article Title",
      #     url: "https://example.com",
      #     enclosure: enclosure_object,
      #     image: "https://example.com/image.jpg"
      #   )
      #   description = builder.call
      class DescriptionBuilder
        # XPath of the attributes whose URLs count as the description already showing a file.
        URL_ATTRIBUTES = './/@src|.//@href|.//@srcset'

        # Removes the first occurrence of the pattern in the text content (never inside a tag or attribute)
        # if it starts before the range's end. Text after a stray +<+ that opens no tag is left alone.
        #
        # @param text [String]
        # @param pattern [String, nil] nothing is removed without one
        # @param end_of_range [Integer] Optional, defaults to half the text length
        # @return [String]
        def self.remove_pattern_from_start(text, pattern, end_of_range: text.size / 2)
          return text unless pattern

          index = text.index(/\A(?:<[^>]*>|[^<])*?\K#{Regexp.escape(pattern)}/)
          return text if index.nil? || index > end_of_range

          "#{text[0, index]}#{text[(index + pattern.size)..]}"
        end

        # @param base [String] The base text content for the description
        # @param title [String] The article title (used for alt text and title removal)
        # @param url [String, Html2rss::Url] The article URL (used for sanitization and URL resolution)
        # @param enclosure [Html2rss::Article::Enclosure, nil] the item's RSS enclosure
        #   ({FeedBuilder::ItemPresentation.rss_enclosure_for}); rendered only when audio or video
        # @param image [String, Html2rss::Url, nil] item image URL, rendered when the enclosure is no player
        def initialize(base:, title:, url:, enclosure:, image:)
          @base = base.to_s
          @title = title
          @url = url
          @player = enclosure if enclosure&.media?
          @image = image
        end

        # Generates the description: the media element (unless the text already shows it) and the sanitized text.
        #
        # @return [String, nil] The complete description or nil if empty
        def call
          text = processed_base_description
          file = @player&.url || @image
          media = media_html if file && !(text && shown?(text, Url.from_absolute(file)))

          parts = [media, text].compact
          parts.join("\n\n") unless parts.empty?
        end

        private

        def media_html
          if @player&.video? then VideoRenderer.new(url: @player.url, type: @player.type).to_html
          elsif @player then AudioRenderer.new(url: @player.url, type: @player.type).to_html
          else ImageRenderer.new(url: @image, title: @title).to_html
          end
        end

        def shown?(text, file)
          text.include?(File.basename(file.path)) && referenced_urls(text).include?(file.to_s)
        end

        def referenced_urls(text)
          Nokogiri::HTML.fragment(text).xpath(URL_ATTRIBUTES).flat_map do |attribute|
            value = attribute.value
            values = attribute.name == 'srcset' ? value.split(',').map { _1[/\S+/] } : [value]
            values.map { resolve(_1) }
          end
        end

        def resolve(value)
          Url.from_relative(value, @url).to_s
        rescue Url::InvalidUrlError
          nil
        end

        def processed_base_description
          text = self.class.remove_pattern_from_start(@base, @title)
          Selectors::PostProcessors::SanitizeHtml.call(text, @url)
        end
      end
    end
  end
end
