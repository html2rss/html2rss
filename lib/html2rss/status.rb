# frozen_string_literal: true

module Html2rss
  ##
  # Shared RSS +generator+ / JSON Feed +user_comment+ formatter string.
  #
  # Exposed publicly via {FeedResult#status}. Safe to log without reading articles.
  # Stable telemetry payload for cross-repo consumers (e.g. html2rss-web observability).
  #
  # @!method to_h
  #   @return [Hash{Symbol => Object}] keys: +:version+ (String), +:scraper_tallies+ (Hash),
  #     +:dedup_dropped+ (Integer), +:selected_strategy+ (Symbol, nil), +:attempt_count+ (Integer)
  Status = Data.define(:version, :scraper_tallies, :dedup_dropped, :selected_strategy, :attempt_count) do
    class << self
      ##
      # Builds status from extracted articles and scrape telemetry.
      #
      # @param articles [Array<Html2rss::Article>] articles kept after deduplication
      # @param dedup_dropped [Integer] number of articles removed by deduplication
      # @param selected_strategy [Symbol, nil] concrete strategy that succeeded under +:auto+ (else +nil+)
      # @param attempt_count [Integer] auto-fallback attempt count (0 when not under +:auto+)
      # @return [Html2rss::Status]
      def build(articles:, dedup_dropped: 0, selected_strategy: nil, attempt_count: 0)
        tallies = articles.filter_map(&:scraper).tally.transform_keys { |klass| scraper_name(klass) }
        new(
          version: Html2rss::VERSION,
          scraper_tallies: tallies.freeze,
          dedup_dropped:,
          selected_strategy:,
          attempt_count:
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
    def initialize(version:, scraper_tallies:, dedup_dropped:, selected_strategy: nil, attempt_count: 0)
      super
    end

    ##
    # Formats the RSS +generator+ string and JSON Feed +user_comment+.
    # Scraper-focused only — auto strategy summary stays on {#to_h}, not this string.
    #
    # @return [String]
    def to_generator_comment
      counts = scraper_tallies.map { |name, count| "#{name} (#{count})" }
      "html2rss V. #{version} (scrapers: #{counts.join(', ')})"
    end
  end
end
