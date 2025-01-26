# frozen_string_literal: true

require 'rss'

module Html2rss
  ##
  # Builds an RSS Feed by providing channel, articles and stylesheets.
  class RssBuilder
    def self.add_guid(article, maker)
      maker.guid.tap do |guid|
        guid.content = article.guid
        guid.isPermaLink = false
      end
    end

    def self.add_item(article, item_maker) # rubocop:disable Metrics/AbcSize
      %w[title description author].each do |attr|
        if (value = article.public_send(attr))
          item_maker.public_send(:"#{attr}=", value)
        end
      end

      item_maker.link = article.url.to_s if article.url
      item_maker.pubDate = article.published_at&.rfc2822

      article.categories.each { |category| item_maker.categories.new_category.content = category }

      Enclosure.add(article.enclosure, item_maker)
      add_guid(article, item_maker)
    end

    ##
    # @param channel [Html2rss::RssBuilder::Channel] The channel information for the RSS feed.
    # @param articles [Array<Html2rss::RssBuilder::Article>] The list of articles to include in the RSS feed
    # @param stylesheets [Array<Html2rss::RssBuilder::Stylesheet>] An optional array of stylesheet URLs
    # @return [Html2rss::RssBuilder] A new instance of the RSSBuilder class
    def initialize(channel:, articles:, stylesheets: [])
      @channel = channel
      @articles = articles
      @stylesheets = stylesheets
    end

    def call
      RSS::Maker.make('2.0') do |maker|
        Stylesheet.add(maker, stylesheets)

        make_channel(maker.channel)
        make_items(maker)
      end
    end

    private

    attr_reader :channel, :articles

    def stylesheets
      @stylesheets.map { |style| Stylesheet.new(**style) }
    end

    def make_channel(maker)
      %i[language title description ttl].each do |key|
        maker.public_send(:"#{key}=", channel.public_send(key))
      end

      maker.link = channel.url.to_s
      maker.generator = generator
      maker.updated = channel.last_build_date
    end

    def make_items(maker)
      articles.each do |article|
        maker.items.new_item { |item_maker| self.class.add_item(article, item_maker) }
      end
    end

    def generator
      scraper_namespace_regex = /(?<namespace>Html2rss|Scraper)::/

      scraper_counts = articles.flat_map(&:scraper).tally.map do |klass, count|
        scraper_name = klass.to_s.gsub(scraper_namespace_regex, '')
        "#{scraper_name} (#{count})"
      end

      "html2rss V. #{Html2rss::VERSION} (scrapers: #{scraper_counts.join(', ')})"
    end
  end
end
