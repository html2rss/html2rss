# frozen_string_literal: true

module Html2rss
  ##
  # Closed Marshal-cacheable handle for one scrape.
  #
  # Frozen consumer query/render set (do not grow without an explicit contract change):
  # {#empty?}, {#channel_title}, {#to_rss}, {#to_json_feed}, and {#status}.
  #
  # Non-goals: no Channel reader, no Articles reader, no peephole into scrape internals.
  # html2rss-web and other consumers must use only this surface.
  #
  # @note Gem contract: instances must round-trip through +Marshal.dump+ / +Marshal.load+
  #   so web can cache one scrape and render RSS or JSON Feed on read. Loaded results
  #   are re-frozen via private {#marshal_load}. For trusted cache reads only,
  #   +Marshal.load(payload, freeze: true)+ is also safe.
  class FeedResult
    ##
    # @param channel [Html2rss::Channel] channel metadata (internal; not exposed on the public API)
    # @param articles [Array<Html2rss::Article>] extracted articles (deduplicated; not exposed)
    # @param status [Html2rss::Status] pipeline telemetry
    # @param stylesheets [Array<Hash>] optional RSS stylesheet configs
    def initialize(channel:, articles:, status:, stylesheets: [])
      raise ArgumentError, 'channel must be a Html2rss::Channel' unless channel.is_a?(Channel)
      raise ArgumentError, 'status must be a Html2rss::Status' unless status.is_a?(Status)

      articles = Array(articles)
      raise ArgumentError, 'articles must all be Html2rss::Article' unless articles.all?(Article)

      @channel = channel
      @articles = articles.dup.freeze
      @status = status
      @stylesheets = freeze_stylesheets(stylesheets)
      freeze
    end

    ##
    # @return [Boolean] true when the scrape produced no items
    def empty? = @articles.empty?

    ##
    # Channel title string only — does not expose the channel object.
    #
    # @return [String] title from the materialized channel
    def channel_title = @channel.title

    ##
    # @return [RSS::Rss] RSS 2.0 document
    def to_rss
      FeedBuilder::Rss.new(
        channel: @channel,
        articles: @articles,
        stylesheets: @stylesheets,
        generator: status.to_generator_comment
      ).call
    end

    ##
    # @param feed_url [String, nil] optional self URL for JSON Feed (+feed_url+)
    # @return [Hash] JSON Feed 1.1 hash
    def to_json_feed(feed_url: nil)
      FeedBuilder::JsonFeed.new(
        channel: @channel,
        articles: @articles,
        feed_url:,
        user_comment: status.to_generator_comment
      ).call
    end

    ##
    # @return [Html2rss::Status] frozen scraper tallies, dedup count, and generator formatter.
    #   {#to_h} on +status+ is a stable consumer contract for observability payloads.
    attr_reader :status

    private

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

    def freeze_stylesheets(stylesheets)
      Array(stylesheets).map do |sheet|
        sheet.to_h.transform_keys(&:to_sym).transform_values do |value|
          value.is_a?(String) ? value.dup.freeze : value
        end.freeze
      end.freeze
    end
  end
end
