# frozen_string_literal: true

module Html2rss
  Status = Data.define(
    :version, :scraper_tallies, :dedup_dropped, :selected_strategy, :attempt_count,
    :strategy_attempts, :admission_drops, :entry_url, :scrape_url, :entry_resolution,
    :enriched, :enrich_failed, :enrich_skipped_cross_origin
  )

  ##
  # Shared RSS +generator+ / JSON Feed +user_comment+ formatter string.
  #
  # Exposed publicly via {FeedResult#status}. Safe to log without reading articles.
  # Stable telemetry payload for cross-repo consumers (e.g. html2rss-web observability).
  # Tallies and counters are validated and frozen at construction (including Marshal load).
  class Status # rubocop:disable Metrics/ClassLength -- one reader and one validated counter per telemetry field
    # Raised when telemetry fields fail validation at construction.
    class InvalidError < Html2rss::ContractError; end

    # Keys kept in {#to_h} even when zero or empty.
    ALWAYS_REPORTED = %i[version dedup_dropped].freeze
    private_constant :ALWAYS_REPORTED

    # Article-enrichment counters (see {FeedPipeline::Enrichment::Result}).
    ENRICHMENT_KEYS = %i[enriched enrich_failed enrich_skipped_cross_origin].freeze
    private_constant :ENRICHMENT_KEYS

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
      # @param scrape_target [Html2rss::FeedPipeline::ScrapeTarget, nil] domain URL pair (mapped to wire strings)
      # @param entry_url [String, nil] original channel URL when entry resolution ran
      # @param scrape_url [String, nil] effective scrape URL after resolution
      # @param entry_resolution [Html2rss::FeedResolution::Diag, Hash, nil] resolution diagnostics
      # @param enrichment [Hash{Symbol => Integer}] {FeedPipeline::Enrichment} tally (empty when off)
      # @return [Html2rss::Status]
      # rubocop:disable-next Metrics/ParameterLists, Metrics/MethodLength -- Status kwargs stay co-located
      def build(articles:, dedup_dropped: 0, selected_strategy: nil, attempt_count: 0,
                strategy_attempts: [], admission_drops: {}, scrape_target: nil,
                entry_url: nil, scrape_url: nil, entry_resolution: nil, enrichment: {})
        tallies = articles.filter_map(&:scraper).tally.transform_keys { |klass| scraper_name(klass) }
        new(
          version: Html2rss::VERSION,
          scraper_tallies: tallies,
          dedup_dropped:,
          selected_strategy:,
          attempt_count:,
          strategy_attempts:,
          admission_drops:,
          entry_url: entry_url || scrape_target&.entry_url,
          scrape_url: scrape_url || scrape_target&.effective_url,
          entry_resolution:,
          **ENRICHMENT_KEYS.to_h { [_1, enrichment.fetch(_1, 0)] }
        )
      end

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
    # @param entry_url [String, nil]
    # @param scrape_url [String, nil]
    # @param entry_resolution [Html2rss::FeedResolution::Diag, Hash, nil]
    # @param enriched [Integer] items that gained a field from their article page
    # @param enrich_failed [Integer] article fetches that failed or were blocked
    # @param enrich_skipped_cross_origin [Integer] fetches skipped by the same-origin policy (subset of enrich_failed)
    # rubocop:disable-next Metrics/ParameterLists, Metrics/MethodLength -- Status Data.define members
    def initialize(
      version:, scraper_tallies:, dedup_dropped:, selected_strategy: nil, attempt_count: 0,
      strategy_attempts: [], admission_drops: {}, entry_url: nil, scrape_url: nil, entry_resolution: nil,
      enriched: 0, enrich_failed: 0, enrich_skipped_cross_origin: 0
    )
      dedup = Option.integer(:dedup_dropped, dedup_dropped, min: 0)
      attempts = Option.integer(:attempt_count, attempt_count, min: 0)
      validate_selected_strategy!(selected_strategy, attempts)

      super(
        version: version.to_s.dup.freeze,
        scraper_tallies: freeze_tallies(scraper_tallies),
        dedup_dropped: dedup,
        selected_strategy:,
        attempt_count: attempts,
        strategy_attempts: freeze_attempts(strategy_attempts),
        admission_drops: freeze_tallies(admission_drops),
        entry_url: freeze_optional_string(entry_url),
        scrape_url: freeze_optional_string(scrape_url),
        entry_resolution: freeze_entry_resolution(entry_resolution),
        enriched: Option.integer(:enriched, enriched, min: 0),
        enrich_failed: Option.integer(:enrich_failed, enrich_failed, min: 0),
        enrich_skipped_cross_origin: Option.integer(:enrich_skipped_cross_origin, enrich_skipped_cross_origin, min: 0)
      )
    end

    ##
    # Observability hash for web (+scraper_status+). Omits empty/absent optional keys.
    #
    # @return [Hash{Symbol => Object}]
    def to_h
      super.reject { |key, value| !ALWAYS_REPORTED.include?(key) && omit?(value) }
    end

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

    def omit?(value)
      case value
      when nil then true
      when Integer then value.zero?
      else value.empty?
      end
    end

    def marshal_dump
      [version, scraper_tallies, dedup_dropped, selected_strategy, attempt_count, strategy_attempts,
       admission_drops, entry_url, scrape_url, entry_resolution, enriched, enrich_failed,
       enrich_skipped_cross_origin]
    end

    def marshal_load(payload)
      version, scraper_tallies, dedup_dropped, selected_strategy, attempt_count,
        strategy_attempts, admission_drops, entry_url, scrape_url, entry_resolution,
        enriched, enrich_failed, enrich_skipped_cross_origin = payload
      initialize(version:, scraper_tallies:, dedup_dropped:, selected_strategy:, attempt_count:,
                 strategy_attempts:, admission_drops:, entry_url:, scrape_url:,
                 entry_resolution:, enriched: enriched || 0, enrich_failed: enrich_failed || 0,
                 enrich_skipped_cross_origin: enrich_skipped_cross_origin || 0)
    end

    def freeze_tallies(tallies)
      tallies.to_h { |name, count| [name.to_s, count] }.freeze
    end

    def freeze_attempts(attempts)
      attempts.map { |attempt| attempt.dup.freeze }.freeze
    end

    def freeze_optional_string(value)
      return if value.nil?

      value.to_s.dup.freeze
    end

    def freeze_entry_resolution(value)
      return if value.nil?

      case value
      when Hash, FeedResolution::Diag then value.to_h
      else
        raise InvalidError, "entry_resolution must be a Hash or FeedResolution::Diag, got #{value.class}"
      end.transform_keys(&:to_sym).freeze
    end

    def validate_selected_strategy!(selected_strategy, attempts)
      return if selected_strategy.nil?
      raise InvalidError, 'selected_strategy must be a Symbol or nil' unless selected_strategy.is_a?(Symbol)
      raise InvalidError, 'attempt_count must be >= 1 when selected_strategy is set' if attempts < 1
    end
  end
end
