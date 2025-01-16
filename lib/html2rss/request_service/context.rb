# frozen_string_literal: true

require 'addressable/uri'

module Html2rss
  class RequestService
    ##
    # Holds information needed to send requests to websites.
    # To be passed down to the RequestService's strategies.
    class Context
      SUPPORTED_URL_SCHEMES = %w[http https].to_set.freeze

      ##
      # @param url [String, Addressable::URI] the URL to request
      # @param headers [Hash] HTTP request headers
      def initialize(url:, headers: {})
        @url = Addressable::URI.parse(url).normalize.freeze
        assert_valid_url!

        @headers = headers
      end

      # @return [Addressable::URI] the parsed and normalized URL
      attr_reader :url

      # @return [Hash] the HTTP request headers
      attr_reader :headers

      private

      ##
      # Validates the URL.
      # @raise [InvalidUrl] if the URL is not valid
      # @raise [UnsupportedUrlScheme] if the URL scheme is not supported
      def assert_valid_url!
        raise InvalidUrl, 'URL must be absolute' unless url.absolute?
        raise InvalidUrl, 'URL must not contain an @ character' if url.to_s.include?('@')

        return if SUPPORTED_URL_SCHEMES.include?(url.scheme)

        raise UnsupportedUrlScheme,
              "URL scheme '#{url.scheme}' is not supported"
      end
    end
  end
end
