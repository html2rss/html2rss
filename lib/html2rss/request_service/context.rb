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
      # @param relation [Symbol] why this request is being made
      # @param origin_url [String, Html2rss::Url, nil] the originating URL for same-origin checks
      # @param policy [Policy] runtime request policy
      # @param budget [Budget, nil] shared request budget for the feed build
      def initialize(url:, headers: {}, **request_options)
        @url = Html2rss::Url.from_relative(url, url)
        @headers = headers
        assign_request_options(request_options)
      end

      # @return [Html2rss::Url] the parsed and normalized URL
      attr_reader :url

      # @return [Hash] the HTTP request headers
      attr_reader :headers

      # @return [Symbol] the request relation
      attr_reader :relation

      # @return [Html2rss::Url] the initial URL for the feed build
      attr_reader :origin_url

      # @return [Policy] the runtime request policy
      attr_reader :policy

      # @return [Budget] the shared request budget
      attr_reader :budget

      ##
      # Builds a follow-up request context sharing headers, budget, and policy.
      #
      # @param url [String, Html2rss::Url] the follow-up URL
      # @param relation [Symbol] why the follow-up is being made
      # @return [Context] derived request context
      def follow_up(url:, relation:)
        self.class.new(
          url:,
          headers:,
          relation:,
          origin_url:,
          policy:,
          budget:
        )
      end

      private

      def assign_request_options(request_options)
        @relation = request_options.fetch(:relation, :initial)
        @policy = request_options.fetch(:policy, Policy.default)
        @origin_url = normalized_origin_url(request_options[:origin_url])
        @budget = request_options.fetch(:budget) { Budget.new(max_requests: policy.max_requests) }
      end

      def normalized_origin_url(origin_url)
        source = origin_url || @url
        Html2rss::Url.from_relative(source, source)
      end
    end
  end
end
