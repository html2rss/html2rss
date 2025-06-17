# frozen_string_literal: true

require 'cgi'

module Html2rss
  class RssBuilder
    ##
    # Builds a sanitized article description from the base text, title, and optional media.
    # Supports image, video, audio, and PDF enclosures.
    class DescriptionBuilder
      def initialize(base:, title:, url:, enclosure:, image:)
        @base = base.to_s
        @title = title
        @url = url
        @enclosure = enclosure
        @enclosure_type = @enclosure&.type.to_s
        @image = image
      end

      def call
        result = (media_fragments << processed_base_description).compact.join("\n").strip
        result.empty? ? nil : result
      end

      private

      def media_fragments
        [].tap do |fragments|
          if image_from_enclosure?
            fragments << render_image_from_enclosure
          elsif @image
            fragments << render_image_from_image
          end

          fragments << render_video if video?
          fragments << render_audio if audio?
          fragments << render_pdf if pdf?
        end
      end

      def image_from_enclosure? = @enclosure_type.start_with?('image/')
      def video? = @enclosure_type.start_with?('video/')
      def audio? = @enclosure_type.start_with?('audio/')
      def pdf? = @enclosure_type.start_with?('application/pdf')

      def render_image_from_enclosure
        title = CGI.escapeHTML(@title)

        %(<img src="#{@enclosure.url}"
               alt="#{title}"
               title="#{title}"
               loading="lazy"
               referrerpolicy="no-referrer"
               decoding="async"
               crossorigin="anonymous">).delete("\n").gsub(/\s+/, ' ')
      end

      def render_image_from_image
        title = CGI.escapeHTML(@title)

        %(<img src="#{@image}"
               alt="#{title}"
               title="#{title}"
               loading="lazy"
               referrerpolicy="no-referrer"
               decoding="async"
               crossorigin="anonymous">).delete("\n").gsub(/\s+/, ' ')
      end

      def render_video
        %(<video controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous" playsinline>
            <source src="#{@enclosure.url}" type="#{@enclosure.type}">
          </video>)
      end

      def render_audio
        %(<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
            <source src="#{@enclosure.url}" type="#{@enclosure.type}">
          </audio>)
      end

      def render_pdf
        %(<iframe src="#{@enclosure.url}" width="100%" height="75vh"
                  sandbox=""
                  referrerpolicy="no-referrer"
                  loading="lazy">
           </iframe>)
      end

      def processed_base_description
        text = Article.remove_pattern_from_start(@base, @title)
        Html2rss::Selectors::PostProcessors::SanitizeHtml.get(text, @url)
      end
    end
  end
end
