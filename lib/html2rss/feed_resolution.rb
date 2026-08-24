# frozen_string_literal: true

module Html2rss
  ##
  # Entry URL tournament for weak homepage/hub extracts.
  #
  # {include:file:lib/html2rss/feed_resolution/README.md}
  module FeedResolution
    # Default entry-resolution options merged into AutoSource::DEFAULT_CONFIG.
    DEFAULT_CONFIG = {
      enabled: true,
      max_probes: 5
    }.freeze

    ##
    # Tournament outcome for one entry-resolution attempt.
    Result = Data.define(:entry_url, :scrape_url, :applied, :reason, :probe_count, :winner_score)

    ##
    # @param auto_source [Hash, nil]
    # @return [Integer] probe slots reserved in the baseline request budget
    def self.request_slots_for(auto_source)
      return 0 unless auto_source

      Options.from_auto_source(auto_source).request_slots
    end

    ##
    # @param entry_url [String, Html2rss::Url]
    # @param response [Html2rss::RequestService::Response]
    # @param session [Html2rss::RequestSession]
    # @param config [Html2rss::Config]
    # @param articles_count [Integer]
    # @param surface_category [Symbol, nil]
    # @return [Result]
    # rubocop:disable Metrics/ParameterLists -- tournament kwargs stay co-located
    def self.call(entry_url:, response:, session:, config:, articles_count:, surface_category: nil)
      Runner.new(
        entry_url:, response:, session:, config:, articles_count:, surface_category:
      ).call
    end
    # rubocop:enable Metrics/ParameterLists

    ##
    # Outcome of {FeedResolution.try_apply!} for the auto-fallback chain.
    ApplyOutcome = Data.define(:scrape_target, :status)

    ##
    # Runs the tournament and, when a winner applies, re-fetches and re-extracts articles.
    #
    # @param pipeline [Html2rss::FeedPipeline]
    # @param config [Html2rss::Config]
    # @param response [Html2rss::RequestService::Response]
    # @param session [Html2rss::RequestSession]
    # @param strategy [Symbol]
    # @param resources [Html2rss::FeedPipeline::RuntimePolicy::Resources]
    # @param articles [Array]
    # @param scrape_target [Html2rss::ScrapeTarget]
    # @param state [Html2rss::FeedPipeline::AutoFallback::AttemptState]
    # @param budget [Html2rss::RequestService::Budget]
    # @return [ApplyOutcome, nil] `:succeeded` when retry extract yielded items; `:applied` when
    #   the effective URL changed but retry did not succeed
    # rubocop:disable Metrics/ParameterLists -- orchestration kwargs stay co-located
    def self.try_apply!(pipeline:, config:, response:, session:, strategy:, resources:, articles:,
                        scrape_target:, state:, budget:)
      Orchestrator.new(
        pipeline:, config:, response:, session:, strategy:, resources:, articles:,
        scrape_target:, state:, budget:
      ).call
    end
    # rubocop:enable Metrics/ParameterLists

    # Tournament + optional retry orchestration for {FeedPipeline::AutoFallback}.
    class Orchestrator
      # Minimum remaining request budget required before probing candidates.
      MIN_BUDGET_REMAINING = 3

      # Error classes that abort resolution instead of falling through (mirrors AutoFallback).
      NON_FALLBACK_ERRORS = FeedPipeline::AutoFallback::NON_FALLBACK_ERRORS

      ##
      # @param pipeline [Html2rss::FeedPipeline]
      # @param config [Html2rss::Config]
      # @param response [Html2rss::RequestService::Response]
      # @param session [Html2rss::RequestSession]
      # @param strategy [Symbol]
      # @param resources [Html2rss::FeedPipeline::RuntimePolicy::Resources]
      # @param articles [Array]
      # @param scrape_target [Html2rss::ScrapeTarget]
      # @param state [Html2rss::FeedPipeline::AutoFallback::AttemptState]
      # @param budget [Html2rss::RequestService::Budget]
      # rubocop:disable Metrics/ParameterLists -- orchestration context stays co-located
      def initialize(pipeline:, config:, response:, session:, strategy:, resources:, articles:,
                     scrape_target:, state:, budget:)
        @pipeline = pipeline
        @config = config
        @response = response
        @session = session
        @strategy = strategy
        @resources = resources
        @articles = articles
        @scrape_target = scrape_target
        @state = state
        @budget = budget
      end
      # rubocop:enable Metrics/ParameterLists

      ##
      # @return [ApplyOutcome, nil]
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- eligibility + tournament + retry path
      def call
        return unless eligible?

        state.mark_resolution_tried!
        resolution = run_tournament
        state.remember_entry_resolution(resolution)
        return unless resolution.applied

        effective = scrape_target.with_effective(resolution.scrape_url)
        return ApplyOutcome.new(scrape_target: effective, status: :succeeded) if retry_with(
          resolution, effective:
        )

        ApplyOutcome.new(scrape_target: effective, status: :applied)
      rescue RequestService::RequestBudgetExceeded
        Log.warn('FeedResolution: entry resolution skipped (request budget exhausted)')
        nil
      rescue *NON_FALLBACK_ERRORS
        raise
      rescue StandardError => error
        Log.warn("FeedResolution: entry resolution retry failed (#{error.class})")
        nil
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      attr_reader :pipeline, :config, :response, :session, :strategy, :resources, :articles,
                  :scrape_target, :state, :budget, :assessment

      def eligible?
        return false if state.resolution_tried?
        return false if response.feed_response?
        return false if budget.remaining_requests < MIN_BUDGET_REMAINING

        @assessment = PageRecon.assess(response:, url: config.url)
        Policy.resolve?(
          config:, articles_count: articles.size, surface_category: assessment.surface_category
        )
      end

      def run_tournament
        FeedResolution.call(
          entry_url: config.url,
          response:,
          session:,
          config:,
          articles_count: articles.size,
          surface_category: assessment.surface_category
        )
      end

      def retry_with(_resolution, effective:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- retry extract path
        retry_session = pipeline.request_session_for(
          config, strategy:, resources:, scrape_url: effective.effective_url
        )
        retry_response = retry_session.fetch_initial_response
        retry_articles, dedup_dropped, admission_drops = pipeline.deduplicated_articles(
          config:, response: retry_response, request_session: retry_session
        )
        state.remember_response(retry_response)
        state.record_items(
          strategy:, items_count: retry_articles.size, transport_meta: retry_response.transport_meta
        )
        return unless retry_articles.size.positive?

        state.succeed!(
          response: retry_response, articles: retry_articles, dedup_dropped:,
          selected_strategy: strategy, attempt_count: state.attempts.size, admission_drops:,
          scrape_target: effective
        )
        true
      end
    end

    # Internal tournament runner (keeps {FeedResolution} a Zeitwerk namespace module).
    class Runner
      ##
      # @param entry_url [String, Html2rss::Url]
      # @param response [Html2rss::RequestService::Response]
      # @param session [Html2rss::RequestSession]
      # @param config [Html2rss::Config]
      # @param articles_count [Integer]
      # @param surface_category [Symbol, nil]
      # rubocop:disable Metrics/ParameterLists -- tournament context stays co-located
      def initialize(entry_url:, response:, session:, config:, articles_count:, surface_category: nil)
        @entry_url = Html2rss::Url.from_absolute(entry_url)
        @response = response
        @session = session
        @config = config
        @articles_count = articles_count.to_i
        @surface_category = surface_category
      end
      # rubocop:enable Metrics/ParameterLists

      ##
      # @return [Result]
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- policy → candidates → probe → select
      def call
        return skip(:policy_skip) unless Policy.resolve?(
          config:, articles_count:, surface_category:
        )

        candidates = CandidateGenerator.call(
          entry_url:,
          response:,
          max: max_probes
        )
        return skip(:no_candidates) if candidates.empty?

        scored = probe_candidates(candidates)
        winner = Scorer.pick_winner(scored:, entry_articles_count: articles_count)
        return skip(:no_winner, probe_count: scored.size) unless winner

        apply(winner, probe_count: scored.size)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      attr_reader :entry_url, :response, :session, :config, :articles_count, :surface_category

      def max_probes
        Options.from_auto_source(config.auto_source).max_probes
      end

      def probe_candidates(candidates)
        probe = Probe.new(request_session: session, origin_url: entry_url)
        candidates.filter_map { |url| probe.call(url) }
      end

      def apply(winner, probe_count:) # rubocop:disable Metrics/MethodLength -- log + Result stay co-located
        Log.info(
          "FeedResolution: entry_host=#{entry_url.host} scrape_host=#{winner.url.host} " \
          "applied=true probe_count=#{probe_count} winner_score=#{winner.score} reason=winner"
        )
        Result.new(
          entry_url: entry_url.to_s,
          scrape_url: winner.url.to_s,
          applied: true,
          reason: :winner,
          probe_count:,
          winner_score: winner.score
        )
      end

      def skip(reason, probe_count: 0) # rubocop:disable Metrics/MethodLength -- log + Result stay co-located
        Log.info(
          "FeedResolution: entry_host=#{entry_url.host} scrape_host=#{entry_url.host} " \
          "applied=false probe_count=#{probe_count} winner_score=nil reason=#{reason}"
        )
        Result.new(
          entry_url: entry_url.to_s,
          scrape_url: entry_url.to_s,
          applied: false,
          reason:,
          probe_count:,
          winner_score: nil
        )
      end
    end
  end
end
