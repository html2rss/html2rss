# frozen_string_literal: true

module Html2rss
  ##
  # Opaque, Marshal-cacheable result of one scrape.
  #
  # Public surface for consumers (including html2rss-web): {#empty?}, {#to_rss},
  # {#to_json_feed}, and {#status}. Articles and channel metadata are not exposed.
  #
  # @note Gem contract: instances must round-trip through +Marshal.dump+ / +Marshal.load+
  #   so web can cache one scrape and render RSS or JSON Feed on read.
  class FeedResult
    ##
    # @param channel [Html2rss::Channel, Html2rss::Channel::Snapshot] channel metadata
    # @param articles [Array<Html2rss::Article>] extracted articles (deduplicated)
    # @param status [Html2rss::Status] pipeline telemetry
    # @param stylesheets [Array<Hash>] optional RSS stylesheet configs
    def initialize(channel:, articles:, status:, stylesheets: [])
      @channel = channel.is_a?(Channel::Snapshot) ? channel : Channel::Snapshot.from(channel)
      @articles = articles.freeze
      @status = status
      @stylesheets = Array(stylesheets).freeze
      freeze
    end

    ##
    # @return [Boolean] true when the scrape produced no items
    def empty? = articles.empty?

    ##
    # @return [RSS::Rss] RSS 2.0 document
    def to_rss
      FeedBuilder.build(:rss, channel:, articles:, stylesheets:, generator: status.to_generator_comment)
    end

    ##
    # @param feed_url [String, nil] optional self URL for JSON Feed (wired in a later phase)
    # @return [Hash] JSON Feed 1.1 hash
    def to_json_feed(feed_url: nil) # rubocop:disable Lint/UnusedMethodArgument -- G2 wires feed_url
      FeedBuilder.build(:json_feed, channel:, articles:)
    end

    ##
    # @return [Html2rss::Status] frozen scraper tallies, dedup_dropped, generator formatter
    attr_reader :status

    private

    attr_reader :channel, :articles, :stylesheets
  end
end
