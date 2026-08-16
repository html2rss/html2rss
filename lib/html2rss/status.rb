# frozen_string_literal: true

module Html2rss
  ##
  # Shared RSS +generator+ / JSON Feed +user_comment+ formatter string.
  #
  # Exposed publicly via {FeedResult#status}. Safe to log without reading articles.
  # Stable telemetry payload for cross-repo consumers (e.g. html2rss-web observability).
  # Tallies and counters are validated and frozen at construction (including Marshal load).
  Status = Data.define(
    :version, :scraper_tallies, :dedup_dropped, :selected_strategy, :attempt_count,
    :strategy_attempts, :admission_drops
  ) do
    class << self
      ##
      # Builds status from extracted articles and scrape telemetry.
      #
      # @param articles [Array<Html2rss::Article>] articles kept after deduplication
      # @param dedup_dropped [Integer] number of articles removed by deduplication
      # @param selected_strategy [Symbol, nil] concrete strategy that succeeded under +:auto+ (else +nil+)
      # @param attempt_count [Integer] auto-fallback attempt count (0 when not under +:auto+)
      # @param strategy_attempts [Array<Hash>] auto-fallback attempt hashes (empty outside +:auto+)
      # @param admission_drops [Hash{String => Integer}] Cleanup reason → count (empty when unused)
      # @return [Html2rss::Status]
      # rubocop:disable Metrics/ParameterLists -- Status kwargs stay co-located
      def build(articles:, dedup_dropped: 0, selected_strategy: nil, attempt_count: 0,
                strategy_attempts: [], admission_drops: {})
        tallies = articles.filter_map(&:scraper).tally.transform_keys { |klass| scraper_name(klass) }
        new(
          version: Html2rss::VERSION,
          scraper_tallies: tallies,
          dedup_dropped:,
          selected_strategy:,
          attempt_count:,
          strategy_attempts:,
          admission_drops:
        )
      end
      # rubocop:enable Metrics/ParameterLists

      ##
      # @param klass [Class, #to_s] scraper class
      # @return [String] short scraper label for tallies / generator text
      def scraper_name(klass)
        klass.to_s.gsub(/(?:Html2rss|Scraper)::/, '')
      end
    end

    ##
    # @param version [String]
    # @param scraper_tallies [Hash{String => Integer}]
    # @param dedup_dropped [Integer]
    # @param selected_strategy [Symbol, nil]
    # @param attempt_count [Integer]
    # @param strategy_attempts [Array<Hash>]
    # @param admission_drops [Hash{String => Integer}]
    # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- Status Data.define members
    def initialize(
      version:, scraper_tallies:, dedup_dropped:, selected_strategy: nil, attempt_count: 0,
      strategy_attempts: [], admission_drops: {}
    )
      dedup = Integer(dedup_dropped)
      attempts = Integer(attempt_count)
      validate_counters!(dedup:, attempts:, selected_strategy:)

      super(
        version: version.to_s.dup.freeze,
        scraper_tallies: freeze_tallies(scraper_tallies),
        dedup_dropped: dedup,
        selected_strategy:,
        attempt_count: attempts,
        strategy_attempts: freeze_attempts(strategy_attempts),
        admission_drops: freeze_tallies(admission_drops)
      )
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

    ##
    # Observability hash for web (+scraper_status+). Omits empty/absent optional keys:
    # +:scraper_tallies+ when empty, +:selected_strategy+ when +nil+, +:attempt_count+ when zero,
    # +:strategy_attempts+ / +:admission_drops+ when empty.
    # Data members remain available via readers even when omitted here.
    #
    # @return [Hash{Symbol => Object}] always +:version+ (String), +:dedup_dropped+ (Integer);
    #   optionally +:scraper_tallies+, +:selected_strategy+, +:attempt_count+,
    #   +:strategy_attempts+, +:admission_drops+
    # rubocop:disable Metrics/AbcSize -- omit-empty optional keys stay explicit
    def to_h
      {
        version:,
        dedup_dropped:,
        **(scraper_tallies.any? ? { scraper_tallies: } : {}),
        **(selected_strategy.nil? ? {} : { selected_strategy: }),
        **(attempt_count.positive? ? { attempt_count: } : {}),
        **(strategy_attempts.any? ? { strategy_attempts: } : {}),
        **(admission_drops.any? ? { admission_drops: } : {})
      }
    end
    # rubocop:enable Metrics/AbcSize

    ##
    # Formats the RSS +generator+ string and JSON Feed +user_comment+.
    # Scraper-focused only — auto strategy summary stays on {#to_h}, not this string.
    # Omits the +(scrapers: …)+ clause when tallies are empty.
    #
    # @return [String]
    def to_generator_comment
      return "html2rss V. #{version}" if scraper_tallies.empty?

      counts = scraper_tallies.map { |name, count| "#{name} (#{count})" }
      "html2rss V. #{version} (scrapers: #{counts.join(', ')})"
    end

    private

    def marshal_dump
      [version, scraper_tallies, dedup_dropped, selected_strategy, attempt_count, strategy_attempts,
       admission_drops]
    end

    def marshal_load((version, scraper_tallies, dedup_dropped, selected_strategy, attempt_count,
                      strategy_attempts, admission_drops))
      initialize(version:, scraper_tallies:, dedup_dropped:, selected_strategy:, attempt_count:,
                 strategy_attempts:, admission_drops: admission_drops || {})
    end

    def freeze_tallies(tallies)
      tallies.to_h.transform_keys(&:to_s).transform_values { |count| Integer(count) }.freeze
    end

    def freeze_attempts(attempts)
      Array(attempts).map { |attempt| attempt.to_h.freeze }.freeze
    end

    def validate_counters!(dedup:, attempts:, selected_strategy:)
      raise ArgumentError, 'dedup_dropped must be >= 0' if dedup.negative?
      raise ArgumentError, 'attempt_count must be >= 0' if attempts.negative?

      unless selected_strategy.nil? || selected_strategy.is_a?(Symbol)
        raise ArgumentError, 'selected_strategy must be a Symbol or nil'
      end

      return unless selected_strategy && attempts < 1

      raise ArgumentError, 'attempt_count must be >= 1 when selected_strategy is set'
    end
  end
end
