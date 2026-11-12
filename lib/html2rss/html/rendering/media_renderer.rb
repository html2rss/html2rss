# frozen_string_literal: true

module Html2rss
  module Html
    module Rendering
      # Factory: picks the appropriate renderer for a given enclosure or fallback image, by the enclosure's own
      # kind predicates ({Article::Enclosure#image?}, +#video?+, +#audio?+).
      class MediaRenderer
        # The MIME type rendered inline as a document.
        PDF_TYPE = 'application/pdf'

        # @param enclosure [Html2rss::Article::Enclosure, nil]
        # @param image [String, Html2rss::Url, nil] Fallback image URL
        # @param title [String]
        # @return [ImageRenderer, VideoRenderer, AudioRenderer, PdfRenderer, nil]
        def self.for(enclosure:, image:, title:)
          return ImageRenderer.new(url: image, title:) if enclosure.nil? && image
          return nil unless enclosure

          renderer_for(enclosure, title:)
        end

        # @param enclosure [Html2rss::Article::Enclosure]
        # @param title [String, nil] title used by image renderer
        # @return [ImageRenderer, VideoRenderer, AudioRenderer, PdfRenderer, nil]
        def self.renderer_for(enclosure, title:)
          url = enclosure.url
          type = enclosure.type
          if enclosure.image? then ImageRenderer.new(url:, title:)
          elsif enclosure.video? then VideoRenderer.new(url:, type:)
          elsif enclosure.audio? then AudioRenderer.new(url:, type:)
          elsif type.casecmp?(PDF_TYPE) then PdfRenderer.new(url:)
          end
        end
        private_class_method :renderer_for
      end
    end
  end
end
