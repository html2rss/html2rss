# frozen_string_literal: true

module Html2rss
  ##
  # The apply verb: builds the feed from a config once and owns its result.
  #
  # CLI, MCP and Ruby callers render the same {Result}. The ship gate is {Result#empty?}: surfaces that
  # ship (CLI, MCP) refuse a feed with zero items, while {Html2rss.apply} returns the empty result
  # without raising.
  module Apply
    ##
    # One apply run: the built feed, its RSS document, and the ship-quality report.
    class Result
      # @return [Html2rss::FeedResult]
      attr_reader :feed_result

      ##
      # @param raw_config [Hash{Symbol => Object}] feed configuration the feed was built from
      # @param pipeline_outcome [Html2rss::FeedPipeline::PipelineOutcome]
      # @param feed_result [Html2rss::FeedResult]
      def initialize(raw_config:, pipeline_outcome:, feed_result:)
        @raw_config = raw_config
        @pipeline_outcome = pipeline_outcome
        @feed_result = feed_result
      end

      ##
      # The ship gate: true when the feed has no items.
      #
      # @return [Boolean]
      def empty? = feed_result.empty?

      ##
      # @return [RSS::Rss] the RSS document (built once)
      def to_rss = (@to_rss ||= feed_result.to_rss)

      ##
      # @param feed_url [String, nil] optional self URL for JSON Feed
      # @return [Hash] JSON Feed 1.1 hash
      def to_json_feed(feed_url: nil) = feed_result.to_json_feed(feed_url:)

      ##
      # @return [Html2rss::Status]
      def status = feed_result.status

      ##
      # @return [Integer] number of items in the rendered RSS document
      def item_count = to_rss.items.size

      ##
      # @return [Html2rss::Test::QualityReport] ship-quality audit of the rendered RSS items (built once)
      def quality_report
        @quality_report ||= Test::Quality.report_for(
          to_rss.items,
          channel_url: @raw_config.dig(:channel, :url),
          config: Config.from_hash(@raw_config),
          feed_result:,
          pipeline_outcome: @pipeline_outcome,
          probe_native_feed: false
        )
      end
    end

    ##
    # @param raw_config [Hash{Symbol => Object}] feed configuration
    # @return [Result]
    def self.call(raw_config)
      outcome, feed_result = FeedPipeline.new(raw_config).to_outcome_and_result
      Result.new(raw_config:, pipeline_outcome: outcome, feed_result:)
    end
  end
end
