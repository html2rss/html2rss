# frozen_string_literal: true

module Html2rss
  module Html
    module Rendering
      # Renders an HTML <img> tag from a URL and title.
      class ImageRenderer
        include EscapedAttributes

        # @param url [String, Html2rss::Url] image URL for the src attribute
        # @param title [String, nil] title/alt text for the image
        def initialize(url:, title:)
          @url = url
          @title = title
        end

        # @return [String] HTML image snippet for article rendering
        def to_html
          attributes = [
            %(src="#{escaped_url}"),
            %(alt="#{escaped_title}"),
            %(title="#{escaped_title}"),
            'loading="lazy"',
            'referrerpolicy="no-referrer"',
            'decoding="async"',
            'crossorigin="anonymous"'
          ]
          "<img #{attributes.join(' ')}>"
        end
      end
    end
  end
end
