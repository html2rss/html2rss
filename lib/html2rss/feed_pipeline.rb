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
    # Runs the pipeline once and returns an opaque, Marshal-cacheable result.
    #
    # @return [Html2rss::FeedResult]
    def to_result
      config = Config.from_hash(raw_config, params: raw_config[:params])
      state = pipeline_state_for(config)
      channel = Channel::Snapshot.from(
        Channel.new(state.fetch(:response), overrides: config.channel)
      )
      status = Status.build(articles: state.fetch(:articles), dedup_dropped: state.fetch(:dedup_dropped))
      FeedResult.new(channel:, articles: state.fetch(:articles), status:, stylesheets: config.stylesheets)
    end

    ##
    # @return [RSS::Rss] generated RSS feed
    def to_rss = to_result.to_rss

    ##
    # @return [Hash] generated JSONFeed 1.1 payload
    def to_json_feed = to_result.to_json_feed

    private

    attr_reader :raw_config

    def pipeline_state_for(config)
      plan = StrategyPlan.resolve(config.strategy)
      resources = RuntimePolicy.resources_for(config)
      if plan.is_a?(StrategyPlan::Auto)
        run_auto_pipeline(config, resources:)
      else
        run_pipeline_for_strategy(config, strategy: plan.strategy, resources:)
      end
    end

    def run_pipeline_for_strategy(config, strategy:, resources:)
      request_session = request_session_for(config, strategy:, resources:)
      response = request_session.fetch_initial_response
      extracted = deduplicated_articles(ExtractionContext.new(config:, response:, request_session:))
      { response:, articles: extracted.fetch(:articles), dedup_dropped: extracted.fetch(:dedup_dropped) }
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
      collected = collect_articles(extraction)
      unique = Article::Deduplicator.new(collected).call
      { articles: unique, dedup_dropped: collected.size - unique.size }
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

    # rubocop:disable Metrics/MethodLength
    def selector_articles(extraction)
      config = extraction.config
      return [] unless (selectors = config.selectors)

      page_responses = extraction.request_session.page_responses(
        extraction.response,
        pagination_config: selectors.dig(:items, :pagination)
      )

      articles = []
      page_responses.each do |page_response|
        page_articles = Selectors.new(page_response, selectors:, time_zone: config.time_zone).articles
        break if page_articles.empty? && articles.any?

        articles.concat(page_articles)
      end
      articles
    end
    # rubocop:enable Metrics/MethodLength

    def auto_source_articles(extraction)
      return [] unless (auto_source = extraction.config.auto_source)

      AutoSource.new(extraction.response, auto_source, request_session: extraction.request_session).articles
    end
  end
end
