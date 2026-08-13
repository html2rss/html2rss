# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Html
    module Rendering
      ##
      # Shared HTML attribute escaping for media renderers.
      module EscapedAttributes
        private

        def escaped_url
          CGI.escapeHTML(@url.to_s)
        end

        def escaped_type
          CGI.escapeHTML(@type.to_s)
        end

        def escaped_title
          CGI.escapeHTML(@title.to_s)
        end
      end
    end
  end
end
