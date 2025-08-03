# frozen_string_literal: true

module Html2rss
  module Rendering
    # Renders an HTML <iframe> for PDF documents.
    class PdfRenderer
      def initialize(url:)
        @url = url
      end

      def to_html
        %(<iframe src="#{@url}" width="100%" height="75vh"
                  sandbox=""
                  referrerpolicy="no-referrer"
                  loading="lazy">
           </iframe>)
      end
    end
  end
end
