require 'rss'
require_relative 'item'

module Html2rss
  class FeedBuilder
    def initialize(config)
      @config = config
    end

    def rss
      RSS::Maker.make('2.0') do |maker|
        add_channel_to_maker(maker)

        feed_items.map do |feed_item|
          add_item_to_items(feed_item, maker.items)
        end
      end
    end

    private

    attr_reader :config

    def add_channel_to_maker(maker)
      %i[language author title description link ttl].each do |attribute_name|
        maker.channel.send("#{attribute_name}=".to_sym, config.send(attribute_name))
      end

      maker.channel.generator = "html2rss V. #{::Html2rss::VERSION}"
      maker.channel.lastBuildDate = Time.now.to_s
    end

    def feed_items
      @feed_items ||= Item.from_url config.url, config
    end

    def add_item_to_items(feed_item, items)
      return unless feed_item.valid?

      items.new_item do |rss_item|
        feed_item.available_attributes.each do |attribute_name|
          rss_item.send("#{attribute_name}=".to_sym, feed_item.send(attribute_name))
        end

        feed_item.categories.each do |category|
          rss_item.categories.new_category.content = category
        end

        rss_item.guid.content = Digest::SHA1.hexdigest(feed_item.title)
        rss_item.guid.isPermaLink = false
      end
    end
  end
end
