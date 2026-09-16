# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class Selectors
    ##
    # Parses response bodies for selector CSS queries. JSON responses become an
    # HTML5 fragment via {ObjectToXmlConverter}; HTML responses reuse the
    # response document. Results are cached by response URL.
    class BodyParser
      ##
      # @param page_response [RequestService::Response]
      # @return [Nokogiri::XML::Node] document or fragment suitable for +css+
      def parsed_body_for(page_response)
        @parsed_bodies ||= {}
        @parsed_bodies[page_response.url] ||= build_document(page_response)
      end

      private

      def build_document(page_response)
        if page_response.json_response?
          fragment = ObjectToXmlConverter.new(page_response.parsed_body).call
          Nokogiri::HTML5.fragment(fragment)
        else
          page_response.parsed_body
        end
      end
    end
  end
end
