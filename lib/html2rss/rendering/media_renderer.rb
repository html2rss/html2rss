# frozen_string_literal: true

module Html2rss
  module Rendering
    # Picks the appropriate media renderer based on the enclosure type or fallback image.
    class MediaRenderer
      def self.for(enclosure:, image:, title:)
        return ImageRenderer.new(url: image, title:) if enclosure.nil? && image
        return nil unless enclosure

        new_from_enclosure(enclosure, title)
      end

      def self.new_from_enclosure(enclosure, title)
        case enclosure.type
        when %r{^image/}
          ImageRenderer.new(url: enclosure.url, title:)
        when %r{^video/}
          VideoRenderer.new(url: enclosure.url, type: enclosure.type)
        when %r{^audio/}
          AudioRenderer.new(url: enclosure.url, type: enclosure.type)
        when 'application/pdf'
          PdfRenderer.new(url: enclosure.url)
        end
      end
    end
  end
end
