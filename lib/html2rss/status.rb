# frozen_string_literal: true

module Html2rss
  ##
  # Frozen pipeline telemetry for one scrape: scraper tallies, dedup drops, and the
  # shared generator / +user_comment+ formatter string.
  #
  # Exposed publicly via {FeedResult#status}. Safe to log without reading articles.
  Status = Data.define(:version, :scraper_tallies, :dedup_dropped) do
    class << self
      ##
      # Builds status from extracted articles and a deduplication drop count.
      #
      # @param articles [Array<Html2rss::Article>] articles kept after deduplication
      # @param dedup_dropped [Integer] number of articles removed by deduplication
      # @return [Html2rss::Status]
      def build(articles:, dedup_dropped: 0)
        tallies = articles.filter_map(&:scraper).tally.transform_keys { |klass| scraper_name(klass) }
        new(version: Html2rss::VERSION, scraper_tallies: tallies.freeze, dedup_dropped:)
      end

      ##
      # @param klass [Class, #to_s] scraper class
      # @return [String] short scraper label for tallies / generator text
      def scraper_name(klass)
        klass.to_s.gsub(/(?:Html2rss|Scraper)::/, '')
      end
    end

    ##
    # Formats the RSS +generator+ / JSON Feed +user_comment+ string.
    #
    # @return [String]
    def to_generator_comment
      counts = scraper_tallies.map { |name, count| "#{name} (#{count})" }
      "html2rss V. #{version} (scrapers: #{counts.join(', ')})"
    end
  end
end
