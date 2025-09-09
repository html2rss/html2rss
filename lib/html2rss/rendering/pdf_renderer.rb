# frozen_string_literal: true

require 'cgi'

module Html2rss
  module Rendering
    # Renders an HTML <iframe> for PDF documents.
    class PdfRenderer
      def initialize(url:)
        @url = url
      end

      def to_html
        %(<iframe src="#{escaped_url}" width="100%" height="75vh"
                  sandbox=""
                  referrerpolicy="no-referrer"
                  loading="lazy">
           </iframe>)
      end

      private

      def escaped_url
        CGI.escapeHTML(@url.to_s)
      end
    end
  end
end
