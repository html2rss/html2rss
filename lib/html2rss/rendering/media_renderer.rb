# frozen_string_literal: true

module Html2rss
  module Rendering
    # Picks the appropriate media renderer based on the enclosure type or fallback image.
    #
    # Factory class that creates the correct renderer for different media types.
    # Supports images, audio, video, and PDF documents.
    #
    # @example With enclosure
    #   MediaRenderer.for(enclosure: enclosure_obj, image: nil, title: "Title")
    #   # => ImageRenderer, VideoRenderer, AudioRenderer, or PdfRenderer
    #
    # @example With fallback image
    #   MediaRenderer.for(enclosure: nil, image: "image.jpg", title: "Title")
    #   # => ImageRenderer
    #
    class MediaRenderer
      # Creates the appropriate media renderer.
      #
      # @param enclosure [Html2rss::RssBuilder::Enclosure, nil] The media enclosure
      # @param image [String, Html2rss::Url, nil] Fallback image URL
      # @param title [String] Title for alt text and accessibility
      # @return [ImageRenderer, VideoRenderer, AudioRenderer, PdfRenderer, nil] The appropriate renderer
      def self.for(enclosure:, image:, title:)
        return ImageRenderer.new(url: image, title:) if enclosure.nil? && image
        return nil unless enclosure

        new_from_enclosure(enclosure, title)
      end

      # @private
      def self.new_from_enclosure(enclosure, title)
        url = enclosure.url
        type = enclosure.type

        create_renderer_for_type(type, url:, title:)
      end

      # @private
      def self.create_renderer_for_type(type, url:, title:)
        case type
        when %r{^image/}
          ImageRenderer.new(url:, title:)
        when %r{^video/}
          VideoRenderer.new(url:, type:)
        when %r{^audio/}
          AudioRenderer.new(url:, type:)
        when 'application/pdf'
          PdfRenderer.new(url:)
        end
      end
    end
  end
end
