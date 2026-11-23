# frozen_string_literal: true

require 'json'

module Html2rss
  ##
  # Entry URL tournament for weak homepage/hub extracts.
  #
  # {include:file:lib/html2rss/feed_resolution/README.md}
  module FeedResolution
    # Raised when the tournament or its policy is handed articles that are not an Array.
    class InvalidError < Html2rss::ContractError; end

    # Default entry-resolution options merged into AutoSource::DEFAULT_CONFIG.
    DEFAULT_CONFIG = {
      enabled: true,
      max_probes: 5
    }.freeze

    ##
    # Tournament outcome for one entry-resolution attempt. +response+ is the winner's already fetched
    # response (nil unless applied), so the caller extracts it without fetching the winner again.
    Result = Data.define(:entry_url, :scrape_url, :applied, :reason, :probe_count, :winner_score, :response)

    ##
    # @param auto_source [Hash, nil]
    # @return [Integer] entry-resolution budget slots (one per probe when enabled)
    def self.request_slots_for(auto_source)
      return 0 unless auto_source

      Options.from_auto_source(auto_source).request_slots
    end

    ##
    # Decides whether the entry page needs a better entry URL and, when it does, probes candidates.
    #
    # @param response [Html2rss::RequestService::Response] the entry page response
    # @param session [Html2rss::RequestSession]
    # @param config [Html2rss::Config]
    # @param articles [Array<Html2rss::Article>] what the entry page extracted
    # @param slots [Integer] request slots the tournament may spend (caps the configured probes)
    # @return [Result, nil] nil when no tournament ran (feed response, policy, or no slots)
    def self.call(response:, session:, config:, articles:, slots:)
      Runner.new(response:, session:, config:, articles:, slots:).call
    end

    # Internal tournament runner (keeps {FeedResolution} a Zeitwerk namespace module).
    class Runner
      ##
      # @param response [Html2rss::RequestService::Response]
      # @param session [Html2rss::RequestSession]
      # @param config [Html2rss::Config]
      # @param articles [Array<Html2rss::Article>]
      # @param slots [Integer] request slots the tournament may spend
      def initialize(response:, session:, config:, articles:, slots:)
        @entry_url = Url.from_absolute(config.url)
        @response = response
        @session = session
        @config = config
        @articles = articles
        @slots = slots
      end

      ##
      # @return [Result, nil] nil when the entry page does not warrant a tournament
      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength -- eligibility → candidates → probe → select
      def call
        return unless eligible?

        candidates = CandidateGenerator.call(
          entry_url:,
          response:,
          vocabulary: Vocabulary[Channel.language_for(response, config.channel)],
          max: max_probes
        )
        return skip(:no_candidates) if candidates.empty?

        scored = probe_candidates(candidates)
        winner = Scorer.pick_winner(scored:, entry_articles_count: articles.size)
        return skip(:no_winner, probe_count: scored.size) unless winner

        apply(winner, probe_count: scored.size)
      end

      private

      attr_reader :entry_url, :response, :session, :config, :articles, :slots

      def eligible?
        return false if response.feed_response? || max_probes < 1

        surface_category = PageRecon.surface_category_for(response:, url: config.url)
        Policy.resolve?(config:, articles:, surface_category:)
      end

      # @return [Integer] configured probes, capped by the request slots left to spend
      def max_probes
        [Options.from_auto_source(config.auto_source).max_probes, slots].min
      end

      def probe_candidates(candidates)
        probe = Probe.new(request_session: session, origin_url: entry_url, channel: config.channel)
        candidates.filter_map { |url| probe.call(url) }
      end

      def apply(winner, probe_count:)
        log(Result.new(
              entry_url: entry_url.to_s, scrape_url: winner.url.to_s, applied: true, reason: :winner,
              probe_count:, winner_score: winner.score, response: winner.response
            ))
      end

      def skip(reason, probe_count: 0)
        log(Result.new(
              entry_url: entry_url.to_s, scrape_url: entry_url.to_s, applied: false, reason:,
              probe_count:, winner_score: nil, response: nil
            ))
      end

      # @param result [Result]
      # @return [Result] the same result, after its structured log line
      def log(result)
        scrape_host = Html2rss::Url.from_absolute(result.scrape_url).host
        Log.info({
          event_name: 'feed_resolution.result',
          host: entry_url.host,
          message: "FeedResolution: entry_host=#{entry_url.host} scrape_host=#{scrape_host} " \
                   "applied=#{result.applied} probe_count=#{result.probe_count} " \
                   "winner_score=#{result.winner_score.inspect} reason=#{result.reason}"
        }.to_json)
        result
      end
    end
  end
end
