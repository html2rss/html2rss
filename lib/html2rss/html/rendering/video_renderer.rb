# frozen_string_literal: true

module Html2rss
  module Html
    module Rendering
      # Renders an HTML <video> tag from a URL and type.
      class VideoRenderer
        include EscapedAttributes

        # @param url [String, Html2rss::Url] media URL for the video source
        # @param type [String] MIME type for the video source
        def initialize(url:, type:)
          @url = url
          @type = type
        end

        # @return [String] HTML video snippet for article rendering
        def to_html
          [
            '<video controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous" playsinline>',
            %(<source src="#{escaped_url}" type="#{escaped_type}">),
            '</video>'
          ].join
        end
      end
    end
  end
end
