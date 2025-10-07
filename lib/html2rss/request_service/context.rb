# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Holds information needed to send requests to websites.
    # To be passed down to the RequestService's strategies.
    class Context
      ##
      # @param url [String, Html2rss::Url] the URL to request
      # @param headers [Hash] HTTP request headers
      # @param options [Hash] additional options for the request strategy
      def initialize(url:, headers: {}, options: {})
        @url = Html2rss::Url.from_relative(url, url)

        @headers = headers
        @options = options || {}
      end

      # @return [Html2rss::Url] the parsed and normalized URL
      attr_reader :url

      # @return [Hash] the HTTP request headers
      attr_reader :headers

      # @return [Hash] strategy-specific options
      attr_reader :options
    end
  end
end
