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
      # @param request [Hash] request specific options passed to strategies
      def initialize(url:, headers: {}, request: {})
        @url = Html2rss::Url.from_relative(url, url)

        @headers = headers
        @request = request
      end

      # @return [Html2rss::Url] the parsed and normalized URL
      attr_reader :url

      # @return [Hash] the HTTP request headers
      attr_reader :headers

      # @return [Hash] the request specific options
      attr_reader :request

      # @return [Hash] browserless specific options
      def browserless = request.fetch(:browserless, {})

      # @return [Hash, nil] preload options for browserless requests
      def browserless_preload = browserless[:preload]
    end
  end
end
