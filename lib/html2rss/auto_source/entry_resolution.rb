# frozen_string_literal: true

require 'json'

module Html2rss
  class AutoSource
    ##
    # Entry URL tournament for weak homepage/hub extracts.
    #
    # {include:file:lib/html2rss/auto_source/entry_resolution/README.md}
    module EntryResolution
      # Raised when the tournament or its policy is handed articles that are not an Array.
      class InvalidError < Html2rss::ContractError; end

      # Default entry-resolution options merged into AutoSource::DEFAULT_CONFIG.
      DEFAULT_CONFIG = {
        enabled: true,
        max_probes: 5,
        scope: 'section'
      }.freeze

      ##
      # Tournament outcome for one entry-resolution attempt. +response+ is the winner's already fetched
      # response (nil unless applied), so the caller extracts it without fetching the winner again.
      Result = Data.define(:entry_url, :scrape_url, :applied, :reason, :probe_count, :winner_score, :response,
                           :out_of_scope)

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

      # Internal tournament runner (keeps {EntryResolution} a Zeitwerk namespace module).
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
        def call
          return unless eligible?

          candidates = generator.call
          return skip(:no_candidates) if candidates.empty?

          scored = probe_candidates(candidates)
          winner = Scorer.pick_winner(scored:, entry_articles_count: articles.size)
          return skip(:no_winner, probe_count: scored.size) unless winner

          apply(winner, probe_count: scored.size)
        end

        private

        attr_reader :entry_url, :response, :session, :config, :articles, :slots

        def generator
          @generator ||= CandidateGenerator.new(
            entry_url:, response:, max: max_probes, scope: Options.from_auto_source(config.auto_source).scope,
            vocabulary: Vocabulary[Channel.language_for(response, config.channel)]
          )
        end

        def eligible?
          return false if response.feed_response? || max_probes < 1

          surface_category = AutoSource::Assessment.surface_category_for(response:)
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
                probe_count:, winner_score: winner.score, response: winner.response, out_of_scope: 0
              ))
        end

        # An entry that kept its own items because every better page lay outside the scope says so.
        def skip(reason, probe_count: 0)
          out_of_scope = generator.out_of_scope_count
          reason = :no_in_scope_winner if out_of_scope.positive?
          log(Result.new(
                entry_url: entry_url.to_s, scrape_url: entry_url.to_s, applied: false, reason:,
                probe_count:, winner_score: nil, response: nil, out_of_scope:
              ))
        end

        # @param result [Result]
        # @return [Result] the same result, after its structured log line
        def log(result)
          scrape_host = Url.from_absolute(result.scrape_url).host
          Log.event(
            :info, 'entry_resolution.result',
            host: entry_url.host,
            message: "EntryResolution: entry_host=#{entry_url.host} scrape_host=#{scrape_host} " \
                     "applied=#{result.applied} probe_count=#{result.probe_count} " \
                     "winner_score=#{result.winner_score.inspect} reason=#{result.reason}"
          )
          result
        end
      end
    end
  end
end
