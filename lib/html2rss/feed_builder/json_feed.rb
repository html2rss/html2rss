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
      # @param feed_url [String, nil] optional self URL for the feed (JSON Feed feed_url)
      # @param user_comment [String, nil] optional generator comment (defaults to {Status})
      def initialize(channel:, articles:, feed_url: nil, user_comment: nil)
        @channel = channel
        @articles = articles
        @feed_url = feed_url
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

      attr_reader :channel, :articles, :feed_url

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
      # @return [String]
      def user_comment
        @user_comment || Status.build(articles:).to_generator_comment
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
