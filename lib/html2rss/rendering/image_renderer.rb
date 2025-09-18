# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Renders an HTML <img> tag from a URL and title.
    class ImageRenderer
      def initialize(url:, title:)
        @url = url
        @title = title
      end

      def to_html
        %(<img src="#{@url}"
              alt="#{escaped_title}"
              title="#{escaped_title}"
              loading="lazy"
              referrerpolicy="no-referrer"
              decoding="async"
              crossorigin="anonymous">).delete("\n").gsub(/\s+/, ' ')
      end

      private

      def escaped_title
        CGI.escapeHTML(@title.to_s)
      end
    end
  end
end
