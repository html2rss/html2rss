# frozen_string_literal: true

module Html2rss
  module Rendering
    # Renders an HTML <video> tag from a URL and type.
    class VideoRenderer
      def initialize(url:, type:)
        @url = url
        @type = type
      end

      def to_html
        %(<video controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous" playsinline>
            <source src="#{@url}" type="#{@type}">
          </video>)
      end
    end
  end
end
