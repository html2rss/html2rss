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
      def initialize(url:, headers: {})
        @url = Html2rss::Url.from_relative(url, url)

        @headers = headers
      end

      # @return [Html2rss::Url] the parsed and normalized URL
      attr_reader :url

      # @return [Hash] the HTTP request headers
      attr_reader :headers
    end
  end
end
