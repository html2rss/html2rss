# frozen_string_literal: true

module Html2rss
  class RequestSession
    ##
    # Carries the runtime request inputs needed to build a RequestSession.
    class RuntimeInput
      ##
      # @param config [Html2rss::Config] validated feed config
      # @return [RuntimeInput] runtime request inputs derived from the config
      def self.from_config(config)
        new(
          url: config.url,
          headers: config.headers,
          strategy: config.strategy,
          request_policy: request_policy_for(config)
        )
      end

      class << self
        private

        def request_policy_for(config)
          RequestService::Policy.new(
            max_requests: effective_max_requests_for(config),
            max_redirects: config.max_redirects
          )
        end

        def effective_max_requests_for(config)
          return config.max_requests if config.explicit_max_requests?

          [baseline_request_budget_for(config), config.max_requests].max
        end

        # Reserve enough budget for the initial request plus predictable follow-ups
        # that the top-level pipeline may trigger during a normal feed build.
        def baseline_request_budget_for(config)
          1 + pagination_follow_up_budget_for(config) + known_auto_source_follow_up_budget_for(config)
        end

        def pagination_follow_up_budget_for(config)
          [config.selectors&.dig(:items, :pagination, :max_pages).to_i - 1, 0].max
        end

        def known_auto_source_follow_up_budget_for(config)
          config.auto_source&.dig(:scraper, :wordpress_api, :enabled) ? 1 : 0
        end
      end

      ##
      # @param url [String, Html2rss::Url] initial request URL
      # @param headers [Hash] normalized request headers
      # @param strategy [Symbol] request strategy to use for the session
      # @param request_policy [RequestService::Policy] request policy for the session
      def initialize(url:, headers:, strategy:, request_policy:)
        @url = Html2rss::Url.from_absolute(url)
        @headers = headers.freeze
        @strategy = strategy
        @request_policy = request_policy
        freeze
      end

      ##
      # @return [Html2rss::Url] initial request URL
      attr_reader :url

      ##
      # @return [Hash] normalized request headers
      attr_reader :headers

      ##
      # @return [Symbol] request strategy to use for the session
      attr_reader :strategy

      ##
      # @return [RequestService::Policy] policy derived from the runtime request inputs
      attr_reader :request_policy
    end
  end
end
