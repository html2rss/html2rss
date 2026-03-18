# frozen_string_literal: true

module Html2rss
  ##
  # Coordinates multi-request feed builds on top of RequestService.
  class RequestSession
    class << self
      ##
      # Builds a request session from a validated runtime config.
      #
      # @param config [Html2rss::Config] validated feed config
      # @param logger [Logger] logger used for operational warnings
      # @return [RequestSession] configured request session
      def for_config(config, logger: Html2rss::Log)
        new(
          context: RequestService::Context.new(
            url: config.url,
            headers: config.headers,
            policy: request_policy_for(config)
          ),
          strategy: config.strategy,
          logger:
        )
      end

      private

      def request_policy_for(config)
        RequestService::Policy.new(
          max_requests: request_budget_for(config),
          max_redirects: config.max_redirects
        )
      end

      def request_budget_for(config)
        max_requests = config.max_requests
        return max_requests if config.request_controls.explicit?(:max_requests)

        [baseline_request_budget(config), max_requests].max
      end

      # Reserve enough budget for the initial request plus predictable follow-ups
      # that the top-level pipeline may trigger during a normal feed build.
      def baseline_request_budget(config)
        1 + pagination_follow_up_budget(config) + known_auto_source_follow_up_budget(config)
      end

      def pagination_follow_up_budget(config)
        [pagination_request_budget(config).to_i - 1, 0].max
      end

      def pagination_request_budget(config)
        config.selectors&.dig(:items, :pagination, :max_pages)
      end

      def known_auto_source_follow_up_budget(config)
        config.auto_source&.dig(:scraper, :wordpress_api, :enabled) ? 1 : 0
      end
    end

    ##
    # @param context [RequestService::Context] initial request context
    # @param strategy [Symbol] request strategy to use for all requests in the session
    # @param logger [Logger] logger used for operational warnings
    def initialize(context:, strategy:, logger: Html2rss::Log)
      @context = context
      @strategy = strategy
      @logger = logger
      @visited_urls = Set.new
    end

    ##
    # Executes the initial request for the session.
    #
    # @return [RequestService::Response] initial response
    def fetch_initial_response
      execute(context).tap { |response| remember!(response.url) }
    end

    ##
    # Executes a follow-up request sharing policy, headers, and budget.
    #
    # @param url [String, Html2rss::Url] follow-up request url
    # @param relation [Symbol] why the follow-up is being made
    # @param origin_url [String, Html2rss::Url] effective origin for same-origin checks
    # @return [RequestService::Response] follow-up response
    def follow_up(url:, relation:, origin_url:)
      execute(context.follow_up(url:, relation:, origin_url:)).tap { |response| remember!(response.url) }
    end

    ##
    # Returns the effective page budget after applying the policy ceiling.
    #
    # @param requested_pages [Integer] configured page budget
    # @return [Integer] effective page budget for the session
    def effective_page_budget(requested_pages)
      effective_pages = [requested_pages, context.policy.max_requests].min
      return effective_pages if effective_pages == requested_pages

      logger.warn(
        "#{self.class}: pagination max_pages=#{requested_pages} " \
        "exceeds system ceiling=#{context.policy.max_requests}; " \
        "clamping to #{effective_pages}"
      )
      effective_pages
    end

    ##
    # Returns the configured request budget for the session.
    #
    # @return [Integer] maximum requests allowed for the feed build
    def max_requests
      context.policy.max_requests
    end

    ##
    # @param url [String, Html2rss::Url] url to query
    # @return [Boolean] whether the url was already visited in this session
    def visited?(url)
      visited_urls.include?(normalize_url(url))
    end

    ##
    # Records a visited url in the session.
    #
    # @param url [String, Html2rss::Url] url to track
    # @return [Set<Html2rss::Url>] visited urls
    def remember!(url)
      visited_urls.add(normalize_url(url))
    end

    private

    attr_reader :context, :strategy, :logger, :visited_urls

    def execute(request_context)
      RequestService.execute(request_context, strategy:).tap do |response|
        logger.debug(
          "#{self.class}: relation=#{request_context.relation} " \
          "request_url=#{request_context.url} final_url=#{response.url} " \
          "status=#{response.status || 'unknown'} content_type=#{response.content_type.inspect} " \
          "bytes=#{response.body.bytesize}"
        )
      end
    end

    def normalize_url(url)
      Html2rss::Url.from_absolute(url)
    end
  end
end
