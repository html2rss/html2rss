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

  # @param articles [Array<Html2rss::Article>]
  # @return [Array<Hash>] the compared fields of each article a feed should render
  def expected_fields(articles)
    renderable(articles).map { fields(_1, _1.guid) }
  end

  # @param articles [Array<Html2rss::Article>]
  # @return [Array<Hash>] the same fields as read back from the built RSS (the guid is the parsed id)
  def actual_fields(articles)
    hashes(articles).map { fields(Html2rss::Article.new(**_1), _1[:id]) }
  end

  # @return [Hash] url, title, publication second, categories, author and guid of +article+
  def fields(article, guid)
    { url: article.url.to_s, title: article.title, published_at: article.published_at.to_time.to_i,
      categories: article.categories, author: article.author, guid: }
  end

  # @return [String] the description read back for a one-article feed with +description+ and +title+
  def description_of(description, title:)
    call([Html2rss::Article.new(url: 'https://example.com/a', title:, description:)]).first&.description.to_s
  end
end
