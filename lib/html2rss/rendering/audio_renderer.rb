# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Renders an HTML <audio> tag from a URL and type.
    class AudioRenderer
      def initialize(url:, type:)
        @url = url
        @type = type
      end

      def to_html
        %(<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
            <source src="#{escaped_url}" type="#{escaped_type}">
          </audio>)
      end

      private

      def escaped_url
        CGI.escapeHTML(@url.to_s)
      end

      def escaped_type
        CGI.escapeHTML(@type.to_s)
      end
    end
  end
end
