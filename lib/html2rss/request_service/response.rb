# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # To be used by strategies to provide their response.
    class Response
      ##
      # @param body [String] the body of the response
      # @param headers [Hash] the headers of the response
      def initialize(body:, headers: {})
        @body = body

        headers = headers.dup
        headers.transform_keys!(&:to_s)
        headers.transform_values!(&:to_s)
        @headers = headers
      end

      # @return [String] the body of the response
      attr_reader :body

      # @return [Hash<String, String>] the headers of the response
      attr_reader :headers
    end
  end
end
