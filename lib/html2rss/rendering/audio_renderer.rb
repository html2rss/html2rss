# frozen_string_literal: true

module Html2rss
  module Rendering
    # Renders an HTML <audio> tag from a URL and title.
    class AudioRenderer
      def initialize(url:, type:)
        @url = url
        @type = type
      end

      def to_html
        %(<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
            <source src="#{@url}" type="#{@type}">
          </audio>)
      end
    end
  end
end
