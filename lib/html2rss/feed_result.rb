# frozen_string_literal: true

module Html2rss
  ##
  # Opaque, Marshal-cacheable result of one scrape.
  #
  # Public surface for consumers (including html2rss-web): {#empty?}, {#to_rss},
  # {#to_json_feed}, and {#status}. Articles and channel metadata are not exposed.
  #
  # @note Gem contract: instances must round-trip through +Marshal.dump+ / +Marshal.load+
  #   so web can cache one scrape and render RSS or JSON Feed on read. Loaded results
  #   are re-frozen via {#marshal_load}.
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
    # @return [Array] constructor payload for Marshal (avoids default ivar thaw)
    def marshal_dump
      [@channel, @articles, @status, @stylesheets]
    end

    ##
    # Rebuilds via {#initialize} so the restored object is frozen again.
    #
    # @param payload [Array] values from {#marshal_dump}
    # @return [void]
    def marshal_load(payload)
      channel, articles, status, stylesheets = payload
      initialize(channel:, articles:, status:, stylesheets:)
    end

    ##
    # @return [Boolean] true when the scrape produced no items
    def empty? = @articles.empty?

    ##
    # @return [RSS::Rss] RSS 2.0 document
    def to_rss
      FeedBuilder.build(:rss, channel: @channel, articles: @articles, stylesheets: @stylesheets,
                              generator: status.to_generator_comment)
    end

    ##
    # @param feed_url [String, nil] optional self URL for JSON Feed (+feed_url+)
    # @return [Hash] JSON Feed 1.1 hash
    def to_json_feed(feed_url: nil)
      FeedBuilder.build(
        :json_feed,
        channel: @channel,
        articles: @articles,
        feed_url:,
        user_comment: status.to_generator_comment
      )
    end

    ##
    # @return [Html2rss::Status] frozen scraper tallies, dedup_dropped, generator formatter
    attr_reader :status
  end
end
