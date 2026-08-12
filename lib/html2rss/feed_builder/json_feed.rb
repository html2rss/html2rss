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
      # @param user_comment [String, nil] optional generator comment (from {Status})
      # @param feed_url [String, nil] optional absolute self URL for the feed
      def initialize(channel:, articles:, user_comment: nil, feed_url: nil)
        @channel = channel
        @articles = articles
        @user_comment = user_comment
        @feed_url = feed_url
      end

      ##
      # Builds and returns the JSONFeed hash.
      #
      # @return [Hash] the JSONFeed-compliant hash
      def call
        base_payload.merge(authors: author_array, items: item_hashes).compact
      end

      private

      attr_reader :channel, :articles, :user_comment, :feed_url

      ##
      # @return [Hash]
      def base_payload
        {
          version: VERSION_URL,
          title: channel.title,
          home_page_url: channel.url.to_s,
          description: channel.description,
          language: channel.language,
          icon: channel.image&.to_s,
          feed_url:,
          user_comment:
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
