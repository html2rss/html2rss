# frozen_string_literal: true

# Builds an RSS document from articles and reads it back with the syndication parser.
module RssRoundtrip
  module_function

  # @return [Html2rss::Channel] a fixed channel on a reserved example domain
  def channel
    Html2rss::Channel.new(title: 'Channel', url: 'https://example.com', description: 'Channel', language: 'en',
                          ttl: 12, last_build_date: Time.utc(2019, 1, 1), image: nil, author: nil)
  end

  # @param articles [Array<Html2rss::Article>]
  # @return [Array<Html2rss::Article>] the articles a feed renders, in order
  def renderable(articles) = articles.select { Html2rss::FeedBuilder::ItemPresentation.renderable?(_1) }

  # @param articles [Array<Html2rss::Article>]
  # @return [Array<Hash>] the article hashes the syndication parser reads from the built RSS
  def hashes(articles)
    xml = Html2rss::FeedBuilder::Rss.new(channel:, articles:, generator: 'spec').call.to_s
    Html2rss::Syndication::Parser.parse(xml).articles
  end

  # @param articles [Array<Html2rss::Article>]
  # @return [Array<Html2rss::Article>] the articles a reader gets back from the built RSS
  def call(articles) = hashes(articles).map { Html2rss::Article.new(**_1) }
end
