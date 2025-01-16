# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # To be used by strategies to provide their response.
    class Response
      ##
      # @param body [String] the body of the response
      # @param headers [Hash] the headers of the response
      def initialize(body:, url:, headers: {})
        @body = body

        headers = headers.dup
        headers.transform_keys!(&:to_s)

        @headers = headers
        @url = url
      end

      # @return [String] the raw body of the response
      attr_reader :body

      # @return [Hash<String, Object>] the headers of the response
      attr_reader :headers

      # @return [Addressable::URI] the URL of the response
      attr_reader :url

      def content_type = headers['content-type'] || ''
      def json_response? = content_type.include?('application/json')
      def html_response? = content_type.include?('text/html')

      def parsed_body
        @parsed_body ||= if html_response?
                           Nokogiri::HTML(body).tap do |doc|
                             # Remove comments from the document
                             doc.xpath('//comment()').each(&:remove)
                           end.freeze
                         elsif json_response?
                           JSON.parse(body, symbolize_names: true).freeze
                         else
                           raise UnsupportedResponseContentType, "Unsupported content type: #{content_type}"
                         end
      end
    end
  end
end
