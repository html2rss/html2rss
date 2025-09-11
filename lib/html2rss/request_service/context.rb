# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Holds information needed to send requests to websites.
    # To be passed down to the RequestService's strategies.
    class Context
      SUPPORTED_URL_SCHEMES = %w[http https].to_set.freeze

      ##
      # @param url [String, Html2rss::Url] the URL to request
      # @param headers [Hash] HTTP request headers
      def initialize(url:, headers: {})
        @url = Html2rss::Url.from_relative(url, url)
        assert_valid_url!

        @headers = headers
      end

      # @return [Html2rss::Url] the parsed and normalized URL
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
