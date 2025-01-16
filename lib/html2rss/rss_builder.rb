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

    def self.add_enclosure(enclosure, maker)
      maker.enclosure.tap do |enclosure_maker|
        enclosure_maker.url = enclosure.url.to_s
        enclosure_maker.type = enclosure.type
        enclosure_maker.length = enclosure.bits_length
      end
    end

    def self.add_item(article, item_maker)
      %w[title description author].each do |attr|
        if (value = article.public_send(attr))
          item_maker.public_send(:"#{attr}=", value)
        end
      end

      item_maker.link = article.url.to_s if article.url

      RssBuilder.add_guid(article, item_maker)
      RssBuilder.add_enclosure(article.enclosure, item_maker) if article.enclosure

      article.categories&.each do |category|
        item_maker.categories.new_category.content = category unless category.to_s.empty?
      end

      item_maker.pubDate = article.published_at.rfc2822 if article.published_at
    end

    ##
    # @param channel [RssBuilder::Channel] The channel information for the RSS feed.
    # @param articles [Array<RssBuilder::Article>] The list of articles to include in the RSS feed.
    # @param stylesheets [Array<RssBuilder::Stylesheet>] An optional array of stylesheet URLs to include in the RSS feed.
    # @return [RSSBuilder] A new instance of the RSSBuilder class.
    def initialize(channel:, articles:, stylesheets: [])
      @channel = channel
      @articles = articles
      @stylesheets = stylesheets
    end

    def call
      RSS::Maker.make('2.0') do |maker|
        Html2rss::RssBuilder::Stylesheet.add(maker, @stylesheets)

        make_channel(maker.channel)
        make_items(maker)
      end
    end

    private

    attr_reader :channel, :articles

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
        maker.items.new_item do |item_maker|
          self.class.add_item(article, item_maker)
        end
      end
    end

    def generator
      scraper_counts = +''

      @articles.each_with_object(Hash.new(0)) { |article, counts| counts[article.scraper] += 1 }
               .each do |klass, count|
        scraper_counts.concat("[#{klass.to_s.gsub('Html2rss::AutoSource::Scraper::', '')}=#{count}]")
      end

      "html2rss V. #{::Html2rss::VERSION} (scrapers: #{scraper_counts})"
    end
  end
end
