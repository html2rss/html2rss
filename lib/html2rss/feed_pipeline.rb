# frozen_string_literal: true

module Html2rss
  ##
  # Builds feeds from validated config through request, extraction, and rendering stages.
  class FeedPipeline
    # Bundle of inputs shared by selector and auto-source article collection.
    ExtractionContext = Data.define(:config, :response, :request_session)

    ##
    # @param raw_config [Hash{Symbol => Object}] user-provided feed config
    def initialize(raw_config)
      @raw_config = raw_config
    end

    ##
    # @return [RSS::Rss] generated RSS feed
    def to_rss
      run do |response:, config:, articles:|
        channel = Html2rss::Channel.new(response, overrides: config.channel)
        RssBuilder.new(channel:, articles:, stylesheets: config.stylesheets).call
      end
    end

    ##
    # @return [Hash] generated JSONFeed 1.1 payload
    def to_json_feed
      run do |response:, config:, articles:|
        channel = Html2rss::Channel.new(response, overrides: config.channel)
        JsonFeedBuilder.new(channel:, articles:).call
      end
    end

    private

    attr_reader :raw_config

    def run
      config = Config.from_hash(raw_config, params: raw_config[:params])
      state = pipeline_state_for(config)
      yield response: state.fetch(:response), config:, articles: state.fetch(:articles)
    end

    def pipeline_state_for(config)
      plan = StrategyPlan.resolve(config.strategy)
      resources = RequestSession::RuntimePolicy.resources_for(config)
      if plan.is_a?(StrategyPlan::Auto)
        run_auto_pipeline(config, resources:)
      else
        run_pipeline_for_strategy(config, strategy: plan.strategy, resources:)
      end
    end

    def run_pipeline_for_strategy(config, strategy:, resources:)
      request_session = request_session_for(config, strategy:, resources:)
      response = request_session.fetch_initial_response
      articles = deduplicated_articles(
        ExtractionContext.new(config:, response:, request_session:)
      )
      { response:, articles: }
    end

    def request_session_for(config, strategy:, resources:)
      RequestSession.build(
        config:,
        strategy:,
        budget: resources.budget,
        policy: resources.policy
      )
    end

    def deduplicated_articles(extraction)
      Articles::Deduplicator.new(collect_articles(extraction)).call
    end

    # rubocop:disable Metrics/MethodLength
    def run_auto_pipeline(config, resources:)
      AutoFallback.new(
        strategies: AutoFallback::CHAIN,
        budget: resources.budget,
        session_for: lambda do |strategy:, budget:|
          budget.effective_timeout_seconds(fallback: resources.policy.total_timeout_seconds)
          request_session_for(config, strategy:, resources:)
        end,
        articles_for: lambda do |response:, request_session:|
          deduplicated_articles(ExtractionContext.new(config:, response:, request_session:))
        end
      ).call
    end
    # rubocop:enable Metrics/MethodLength

    def collect_articles(extraction)
      selector_articles(extraction) + auto_source_articles(extraction)
    end

    def selector_articles(extraction) # rubocop:disable Metrics/MethodLength
      config = extraction.config
      return [] unless (selectors = config.selectors)

      page_responses = if (pagination_config = selectors.dig(:items, :pagination))
                         RequestSession::Pager.for(
                           pagination_config,
                           session: extraction.request_session,
                           initial_response: extraction.response
                         )
                       else
                         [extraction.response]
                       end

      articles = []
      page_responses.each do |page_response|
        page_articles = Selectors.new(page_response, selectors:, time_zone: config.time_zone).articles
        break if page_articles.empty? && articles.any?

        articles.concat(page_articles)
      end
      articles
    end

    def auto_source_articles(extraction)
      return [] unless (auto_source = extraction.config.auto_source)

      AutoSource.new(extraction.response, auto_source, request_session: extraction.request_session).articles
    end
  end
end
