# frozen_string_literal: true

require 'cgi/escape'

module Html2rss
  module FeedBuilder
    module Rendering
      # Renders the one media element of a feed item description: an image, or an audio or video player.
      # Every attribute value is HTML-escaped; each snippet is a single line.
      module Media
        # Opening tags of the media players, keyed by the +<source>+ parent element.
        PLAYER_OPEN_TAGS = {
          audio: '<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">',
          video: '<video controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous" playsinline>'
        }.freeze
        # Constant attributes of the image element.
        IMAGE_ATTRIBUTES = 'loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous"'

        class << self
          # @param url [String, Html2rss::Url] image URL for the src attribute
          # @param title [String, nil] title/alt text for the image
          # @return [String] HTML image snippet
          def image(url:, title:)
            alt = CGI.escapeHTML(title.to_s)
            %(<img src="#{CGI.escapeHTML(url.to_s)}" alt="#{alt}" title="#{alt}" #{IMAGE_ATTRIBUTES}>)
          end

          # @param kind [Symbol] +:audio+ or +:video+
          # @param url [String, Html2rss::Url] media URL for the source
          # @param type [String] MIME type for the source
          # @return [String] HTML player snippet
          def player(kind, url:, type:)
            source = %(<source src="#{CGI.escapeHTML(url.to_s)}" type="#{CGI.escapeHTML(type.to_s)}">)
            "#{PLAYER_OPEN_TAGS.fetch(kind)}#{source}</#{kind}>"
          end
        end
      end
    end
  end
end
