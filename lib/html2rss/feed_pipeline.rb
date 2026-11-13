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
    # feed_channel: channel facts of the native feed followed ({Syndication::ChannelFacts}); nil without one.
    PipelineOutcome = Data.define(
      :response, :articles, :dedup_dropped, :selected_strategy, :attempt_count, :strategy_attempts,
      :admission_drops, :scrape_target, :entry_resolution, :feed_channel
    )

    # What one response yields after extraction and dedup ({#extract}); its fields are the
    # {PipelineOutcome} fields of the same names.
    # articles: unique articles. dedup_dropped: articles removed by deduplication.
    # admission_drops: Cleanup drop tallies. feed_channel: the followed native feed's channel facts
    # ({Syndication::ChannelFacts}); nil without one.
    Extraction = Data.define(:articles, :dedup_dropped, :admission_drops, :feed_channel)

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
    # Runs the pipeline once and returns scrape outcome plus {FeedResult} without a second fetch.
    #
    # @return [Array(PipelineOutcome, FeedResult)]
    def to_outcome_and_result
      config = Config.from_hash(raw_config, params: raw_config[:params])
      outcome = pipeline_outcome_for(config)
      [outcome, feed_result_for(config, outcome)]
    end

    ##
    # Runs the pipeline once and returns an opaque, Marshal-cacheable result.
    #
    # @return [Html2rss::FeedResult]
    def to_result
      config = Config.from_hash(raw_config, params: raw_config[:params])
      outcome = pipeline_outcome_for(config)
      feed_result_for(config, outcome)
    end

    # @api private Host seam for {AutoFallback} (and single-strategy path).
    # @param config [Html2rss::Config]
    # @param strategy [Symbol]
    # @param resources [Html2rss::FeedPipeline::RuntimePolicy::Resources]
    # @param scrape_url [String, nil] effective fetch URL override for resolved targets
    # @return [Html2rss::RequestSession]
    def request_session_for(config, strategy:, resources:, scrape_url: nil)
      RequestSession.build(
        config:,
        strategy:,
        budget: resources.budget,
        policy: resources.policy,
        scrape_url:
      )
    end

    # @api private Host seam for {AutoFallback} (and single-strategy path).
    # @param config [Html2rss::Config]
    # @param response [Html2rss::RequestService::Response]
    # @param request_session [Html2rss::RequestSession]
    # @return [Extraction] unique articles with their dedup and admission drops and feed channel facts
    def extract(config:, response:, request_session:)
      collected, admission_drops, feed_channel = collect_articles(config:, response:, request_session:)
      unique = Article::Deduplicator.new(collected).call
      Extraction.new(articles: unique, dedup_dropped: collected.size - unique.size, admission_drops:, feed_channel:)
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
      extraction = extract(config:, response:, request_session:)
      raise_empty_auto_source!(strategy:, response:) if config.auto_source && extraction.articles.empty?

      PipelineOutcome.new(
        response:, selected_strategy: nil, attempt_count: 0, strategy_attempts: [],
        scrape_target: ScrapeTarget.from_config(config), entry_resolution: nil, **extraction.to_h
      )
    end

    def raise_empty_auto_source!(strategy:, response:)
      raise NoFeedItemsExtracted.new(
        attempts: [{ strategy:, items_count: 0, error_class: nil }],
        surface_category: empty_auto_source_surface(response)
      )
    end

    def empty_auto_source_surface(response)
      PageRecon.surface_category_for(response:, url: response.url)
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
      selector, selector_drops = selector_articles(config:, response:, request_session:)
      auto, auto_drops, feed_channel = auto_source_articles(config:, response:, request_session:)
      [selector + auto, selector_drops.merge(auto_drops) { |_reason, left, right| left + right }, feed_channel]
    end

    # @return [Array(Array<Html2rss::Article>, Hash{String => Integer})] articles and unlinked-item drop tallies
    def selector_articles(config:, response:, request_session:)
      return [[], {}] unless (selectors = config.selectors)
      return [[], {}] if response.feed_response?

      page_responses = request_session.page_responses(
        response,
        pagination_config: selectors.dig(:items, :pagination)
      )
      engines = page_responses.lazy.map { |page| Selectors.new(page, selectors:, time_zone: config.time_zone) }
      collect_selector_pages(engines)
    end

    # Stops at the first empty page after articles were found; drop tallies sum over the pages read.
    def collect_selector_pages(engines)
      articles = []
      drops = Hash.new(0)
      engines.each do |engine|
        page_articles = engine.articles
        break if page_articles.empty? && articles.any?

        articles.concat(page_articles)
        engine.admission_drops.each { |reason, count| drops[reason] += count }
      end
      [articles, drops]
    end

    # @return [Array(Array<Html2rss::Article>, Hash{String => Integer}, Html2rss::Syndication::ChannelFacts)]
    def auto_source_articles(config:, response:, request_session:)
      return [[], {}, nil] unless (auto_source = config.auto_source)
      return syndication_articles(response) if response.feed_response?

      source = AutoSource.new(response, auto_source, request_session:)
      [source.articles, source.admission_drops, source.feed_channel]
    end

    def syndication_articles(response)
      feed = Syndication::Parser.parse_response(response)
      articles = feed.articles.map { |hash| Article.new(**hash, scraper: AutoSource::Scraper::NativeFeed) }
      [articles, {}, feed.channel]
    end

    def feed_result_for(config, outcome) # rubocop:disable Metrics/MethodLength
      channel = Channel.from_response(outcome.response, overrides: config.channel, feed: outcome.feed_channel)
      status = Status.build(
        articles: outcome.articles,
        dedup_dropped: outcome.dedup_dropped,
        selected_strategy: outcome.selected_strategy,
        attempt_count: outcome.attempt_count,
        strategy_attempts: outcome.strategy_attempts,
        admission_drops: outcome.admission_drops,
        scrape_target: outcome.scrape_target,
        entry_resolution: outcome.entry_resolution
      )
      FeedResult.new(channel:, articles: outcome.articles, status:, stylesheets: config.stylesheets)
    end
  end
end
