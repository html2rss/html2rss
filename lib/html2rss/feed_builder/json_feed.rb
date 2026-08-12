# frozen_string_literal: true

module Html2rss
  module FeedBuilder
    ##
    # Builds a JSONFeed 1.1 hash from channel metadata and articles.
    #
    # @see https://www.jsonfeed.org/version/1.1/
    class JsonFeed
      # Official JSON Feed 1.1 schema version URL.
      VERSION_URL = 'https://jsonfeed.org/version/1.1'

      ##
      # @param channel [Html2rss::Channel]
      # @param articles [Array<Html2rss::Article>]
      # @param user_comment [String] required generator comment (from {Status})
      # @param feed_url [String, nil] optional absolute self URL for the feed (JSON Feed feed_url)
      def initialize(channel:, articles:, user_comment:, feed_url: nil)
        raise ArgumentError, 'user_comment must be a non-blank String' if blank_string?(user_comment)

        @channel = channel
        @articles = articles
        @feed_url = normalize_feed_url(feed_url)
        @user_comment = user_comment
      end

      ##
      # Builds and returns the JSONFeed hash.
      #
      # @return [Hash] the JSONFeed-compliant hash
      def call
        base_payload.merge(authors: author_array, items: item_hashes).compact
      end

      private

      attr_reader :channel, :articles, :feed_url, :user_comment

      def blank_string?(value)
        !value.is_a?(String) || value.strip.empty?
      end

      def normalize_feed_url(value)
        return if value.nil?
        raise ArgumentError, 'feed_url must be a String or nil' unless value.is_a?(String)
        return if value.strip.empty?

        Url.from_absolute(value).to_s
      end

      ##
      # @return [Hash]
      def base_payload
        {
          version: VERSION_URL,
          title: channel.title,
          home_page_url: channel.url.to_s,
          feed_url:,
          description: channel.description,
          user_comment:,
          language: channel.language,
          icon: channel.image&.to_s
        }
      end

      ##
      # @return [Array<Hash>]
      def item_hashes
        articles.filter_map { |article| Item.new(article).to_h }
      end

      ##
      # @return [Array<Hash>, nil]
      def author_array
        return unless (name = channel.author)

        [{ name: }]
      end
    end
  end
end
