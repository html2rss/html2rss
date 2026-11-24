# frozen_string_literal: true

module Html2rss
  ##
  # Coordinates multi-request feed builds on top of RequestService.
  class RequestSession
    class << self
      ##
      # Builds a request session from config, strategy, and shared budget/policy.
      #
      # Context owns URL/header/request normalization once; callers must not
      # pre-normalize through a passthrough bag.
      #
      # @param config [Html2rss::Config] validated feed config
      # @param strategy [Symbol] request strategy for the session
      # @param budget [RequestService::Budget] shared request budget
      # @param policy [RequestService::Policy] request policy (from FeedPipeline::RuntimePolicy.resources_for)
      # @param scrape_url [String, nil] effective fetch URL when it differs from config channel URL
      # @param logger [Logger] logger used for operational warnings
      # @return [RequestSession] configured request session
      # rubocop:disable-next Metrics/ParameterLists -- scrape_url override stays beside config
      def build(config:, strategy:, budget:, policy:, scrape_url: nil, logger: Html2rss::Log)
        context = RequestService::Context.new(
          url: scrape_url || config.url, headers: config.headers, request: config.request, policy:, budget:
        )
        new(context:, strategy:, logger:)
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
      @follow_ups = {}
    end

    ##
    # Executes the initial request for the session.
    #
    # @return [RequestService::Response] initial response
    def fetch_initial_response
      execute(context).tap { |response| remember!(response.url) }
    end

    ##
    # Returns an enumerable sequence of page responses for the given initial response
    # and optional pagination configuration.
    #
    # @param initial_response [RequestService::Response] initial page response
    # @param pagination_config [Hash, Integer, nil] pagination configuration
    # @return [Enumerable<RequestService::Response>] page responses
    def page_responses(initial_response, pagination_config: nil)
      return [initial_response] unless pagination_config

      Pager.for(pagination_config, session: self, initial_response:)
    end

    ##
    # Returns a session with the same strategy, policy, headers and origin but its own request budget, so a
    # bounded optional step (article enrichment) cannot spend the listing's request slots. The wall clock is
    # the remaining time of this session's budget (rounded up, at least one second).
    #
    # @param max_requests [Integer] request slots of the new budget
    # @return [RequestSession]
    def with_budget_allowance(max_requests)
      self.class.new(context: allowance_context(max_requests), strategy:, logger:)
    end

    ##
    # Executes a follow-up request sharing policy, headers, and budget. A URL answered with a
    # successful response is fetched once per session: a later follow-up to it (another relation
    # included) passes the policy for its own relation, then reuses the response without spending a
    # request. The memo dies with the session, and the budget bounds its size.
    #
    # @param url [String, Html2rss::Url] follow-up request url
    # @param relation [Symbol] why the follow-up is being made
    # @param origin_url [String, Html2rss::Url] effective origin for same-origin checks
    # @param advertisement [RequestService::FeedAdvertisement, nil] the origin page's advertised feeds;
    #   with relation +:advertised_feed+, {RequestService::Policy} lets a listed feed leave the origin
    # @return [RequestService::Response] follow-up response
    def follow_up(url:, relation:, origin_url:, advertisement: nil)
      request_context = context.follow_up(url:, relation:, origin_url:, advertisement:)
      memoized = @follow_ups[request_context.url]
      unless memoized
        return execute(request_context).tap do |response|
          remember_follow_up!(request_context.url, response)
        end
      end

      validate_reuse!(request_context)
      memoized
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
    # @param url [String, Html2rss::Url] follow-up target URL for the request
    # @return [Boolean] whether the url was already visited in this session
    def visited?(url)
      visited_urls.include?(normalize_url(url))
    end

    ##
    # Records a visited url in the session.
    #
    # @param url [String, Html2rss::Url] URL used to update relation tracking state
    # @return [Set<Html2rss::Url>] visited urls
    def remember!(url)
      visited_urls.add(normalize_url(url))
    end

    ##
    # @return [Html2rss::Url] the session's current request URL
    def url = context.url

    private

    attr_reader :context, :strategy, :logger, :visited_urls

    def allowance_context(max_requests)
      remaining = context.budget.remaining_timeout_seconds
      budget = RequestService::Budget.new(max_requests:, total_timeout_seconds: [remaining.ceil, 1].max)
      RequestService::Context.new(
        url:, headers: context.headers, request: context.request, policy: context.policy, budget:,
        origin_url: context.origin_url
      )
    end

    def validate_reuse!(request_context)
      request_context.policy.validate_request!(
        url: request_context.url, origin_url: request_context.origin_url,
        relation: request_context.relation, advertisement: request_context.advertisement
      )
    end

    def remember_follow_up!(requested_url, response)
      remember!(response.url)
      @follow_ups[requested_url] = response if response.status.nil? || response.status.between?(200, 299)
    end

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
