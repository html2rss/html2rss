# frozen_string_literal: true

module Html2rss
  ##
  # Builds a JSONFeed 1.1 hash from channel metadata and articles.
  #
  # @see https://www.jsonfeed.org/version/1.1/
  class JsonFeedBuilder
    VERSION_URL = 'https://jsonfeed.org/version/1.1'

    ##
    # @param channel [Html2rss::RssBuilder::Channel]
    # @param articles [Array<Html2rss::RssBuilder::Article>]
    def initialize(channel:, articles:)
      @channel = channel
      @articles = articles
    end

    ##
    # Builds and returns the JSONFeed hash.
    #
    # @return [Hash] the JSONFeed-compliant hash
    def call
      {
        version: VERSION_URL,
        title: channel.title,
        home_page_url: channel.url.to_s,
        description: channel.description,
        language: channel.language,
        icon: channel.image&.to_s,
        authors: author_array,
        items: articles.filter_map { |article| Item.new(article).to_h }
      }.compact
    end

    private

    attr_reader :channel, :articles

    ##
    # @return [Array<Hash>, nil]
    def author_array
      return unless (name = channel.author)

      [{ name: }]
    end
  end
end
