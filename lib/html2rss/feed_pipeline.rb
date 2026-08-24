# frozen_string_literal: true

module Html2rss
  ##
  # Builds feeds from validated config through request, extraction, and rendering stages.
  #
  # {include:file:lib/html2rss/feed_pipeline/README.md}
  class FeedPipeline # rubocop:disable Metrics/ClassLength -- outcome + collect seams stay co-located
    # Scrape-finished facts after request + extraction + dedup (before Channel/Status materialize).
    # selected_strategy: set on :auto success; nil otherwise.
    # attempt_count: auto attempts attempted; 0 outside :auto.
    # strategy_attempts: auto attempt hashes (with optional transport_meta); empty outside :auto.
    PipelineOutcome = Data.define(
      :response, :articles, :dedup_dropped, :selected_strategy, :attempt_count, :strategy_attempts,
      :admission_drops
    )

    ##
    # @param raw_config [Hash{Symbol => Object}] user-provided feed config
    def initialize(raw_config)
      @raw_config = raw_config
    end

    ##
    # Runs the pipeline once and returns scrape-finished outcome (before Channel/Status).
    # Used by {Capture} which needs the response body for SST selector derivation.
    #
    # @return [PipelineOutcome]
    def to_outcome
      config = Config.from_hash(raw_config, params: raw_config[:params])
      pipeline_outcome_for(config)
    end

    ##
    # Runs the pipeline once and returns an opaque, Marshal-cacheable result.
    #
    # @return [Html2rss::FeedResult]
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- Status kwargs stay co-located with Channel
    def to_result
      config = Config.from_hash(raw_config, params: raw_config[:params])
      outcome = pipeline_outcome_for(config)
      channel = Channel.from_response(outcome.response, overrides: config.channel)
      status = Status.build(
        articles: outcome.articles,
        dedup_dropped: outcome.dedup_dropped,
        selected_strategy: outcome.selected_strategy,
        attempt_count: outcome.attempt_count,
        strategy_attempts: outcome.strategy_attempts,
        admission_drops: outcome.admission_drops
      )
      FeedResult.new(channel:, articles: outcome.articles, status:, stylesheets: config.stylesheets)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # @api private Host seam for {AutoFallback} (and single-strategy path).
    # @param config [Html2rss::Config]
    # @param strategy [Symbol]
    # @param resources [Html2rss::FeedPipeline::RuntimePolicy::Resources]
    # @return [Html2rss::RequestSession]
    def request_session_for(config, strategy:, resources:)
      RequestSession.build(
        config:,
        strategy:,
        budget: resources.budget,
        policy: resources.policy
      )
    end

    # @api private Host seam for {AutoFallback} (and single-strategy path).
    # @param config [Html2rss::Config]
    # @param response [Html2rss::RequestService::Response]
    # @param request_session [Html2rss::RequestSession]
    # @return [Array(Array<Html2rss::Article>, Integer, Hash)] unique articles, dedup drops, admission drops
    def deduplicated_articles(config:, response:, request_session:)
      collected, admission_drops = collect_articles(config:, response:, request_session:)
      unique = Article::Deduplicator.new(collected).call
      [unique, collected.size - unique.size, admission_drops]
    end

    private

    attr_reader :raw_config

    def pipeline_outcome_for(config)
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
      articles, dedup_dropped, admission_drops = deduplicated_articles(config:, response:, request_session:)
      raise_empty_auto_source!(strategy:, response:) if config.auto_source && articles.empty?

      PipelineOutcome.new(
        response:, articles:, dedup_dropped:, selected_strategy: nil, attempt_count: 0,
        strategy_attempts: [], admission_drops:
      )
    end

    def run_auto_pipeline(config, resources:)
      AutoFallback.new(
        strategies: AutoFallback::CHAIN,
        budget: resources.budget,
        pipeline: self,
        config:,
        resources:
      ).call
    end

    def collect_articles(config:, response:, request_session:)
      selector = selector_articles(config:, response:, request_session:)
      auto, admission_drops = auto_source_articles(config:, response:, request_session:)
      [selector + auto, admission_drops]
    end

    # rubocop:disable Metrics/MethodLength
    def selector_articles(config:, response:, request_session:)
      return [] unless (selectors = config.selectors)
      return [] if response.feed_response?

      page_responses = request_session.page_responses(
        response,
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

    # @return [Array(Array<Html2rss::Article>, Hash{String => Integer})]
    def auto_source_articles(config:, response:, request_session:)
      return [[], {}] unless (auto_source = config.auto_source)
      return syndication_articles(response) if response.feed_response?

      source = AutoSource.new(response, auto_source, request_session:)
      [source.articles, source.admission_drops]
    end

    def syndication_articles(response)
      articles = Syndication::Parser.parse_response(response).map do |hash|
        Article.new(**hash, scraper: AutoSource::Scraper::NativeFeed)
      end
      [articles, {}]
    end

    def raise_empty_auto_source!(strategy:, response:)
      raise NoFeedItemsExtracted.new(
        attempts: [{ strategy:, items_count: 0, error_class: nil }],
        surface_category: empty_auto_source_surface(response)
      )
    end

    def empty_auto_source_surface(response)
      return :unsupported_surface if response.feed_response?

      AutoSource::Scraper.classify_no_scraper_surface(response.parsed_body, body: response.body)
    end
  end
end
