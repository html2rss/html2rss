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

    Result = Data.define(:entry_url, :scrape_url, :applied, :reason, :probe_count, :winner_score)

    ##
    # @param entry_url [String, Html2rss::Url]
    # @param response [Html2rss::RequestService::Response]
    # @param session [Html2rss::RequestSession]
    # @param config [Html2rss::Config]
    # @param articles_count [Integer]
    # @param surface_category [Symbol, nil]
    # @return [Result]
    def self.call(entry_url:, response:, session:, config:, articles_count:, surface_category: nil)
      Runner.new(
        entry_url:, response:, session:, config:, articles_count:, surface_category:
      ).call
    end

    # Internal tournament runner (keeps {FeedResolution} a Zeitwerk namespace module).
    class Runner
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
        winner = Selector.call(scored:, entry_articles_count: articles_count)
        return skip(:no_winner, probe_count: scored.size) unless winner

        apply(winner, probe_count: scored.size)
      end

      private

      attr_reader :entry_url, :response, :session, :config, :articles_count, :surface_category

      def max_probes
        config.auto_source.dig(:entry_resolution, :max_probes) || DEFAULT_CONFIG[:max_probes]
      end

      def probe_candidates(candidates)
        probe = Probe.new(request_session: session, origin_url: entry_url)
        candidates.filter_map { |url| probe.call(url) }
      end

      def apply(winner, probe_count:)
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

      def skip(reason, probe_count: 0)
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
