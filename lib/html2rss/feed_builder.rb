require 'rss'
require 'mime/types'

module Html2rss
  ##
  # The purpose is to build the feed, consisting of
  #
  # - the 'channel' and
  # - the 'item'
  #
  # parts.
  class FeedBuilder
    def initialize(config)
      @config = config
    end

    ##
    # @return [RSS:Rss]
    def rss
      RSS::Maker.make('2.0') do |maker|
        add_channel(maker)

        feed_items.map { |feed_item| add_item(feed_item, maker.items.new_item) }
      end
    end

    private

    attr_reader :config

    def add_channel(maker)
      %i[language author title description link ttl].each do |attribute_name|
        maker.channel.public_send("#{attribute_name}=".to_sym, config.public_send(attribute_name))
      end

      maker.channel.generator = "html2rss V. #{::Html2rss::VERSION}"
      maker.channel.lastBuildDate = Time.now.to_s
    end

    def feed_items
      @feed_items ||= Item.from_url(config.url, config).keep_if(&:valid?)
    end

    def add_item(feed_item, rss_item)
      feed_item.available_attributes.each do |attribute_name|
        rss_item.public_send("#{attribute_name}=".to_sym, feed_item.public_send(attribute_name))
      end

      feed_item.categories.each { |category| rss_item.categories.new_category.content = category }
      add_enclosure_from_url(feed_item.enclosure_url, rss_item) if config.attribute?(:enclosure)

      add_guid(feed_item, rss_item)
    end

    def add_enclosure_from_url(url, rss_item)
      content_type = MIME::Types.type_for(File.extname(url).delete('.'))

      rss_item.enclosure.type = if content_type && content_type.first
                                  content_type.first.to_s
                                else
                                  'application/octet-stream'
                                end
      rss_item.enclosure.length = 0
      rss_item.enclosure.url = url
    end

    def add_guid(feed_item, rss_item)
      rss_item.guid.content = Digest::SHA1.hexdigest(feed_item.title)
      rss_item.guid.isPermaLink = false
    end
  end
end
