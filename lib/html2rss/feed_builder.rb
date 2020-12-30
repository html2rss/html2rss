# frozen_string_literal: true

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
    ##
    # @param config [Html2rss::Config]
    def initialize(config)
      @config = config
    end

    ##
    # @return [RSS::Rss]
    def rss
      RSS::Maker.make('2.0') do |maker|
        add_channel(maker.channel)

        items.each { |item| add_item(item, maker.items.new_item) }
      end
    end

    ##
    # @param categories [Array<String>]
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def self.add_categories(categories, item_maker)
      categories.each { |category| item_maker.categories.new_category.content = category }
    end

    ##
    # @param url [String]
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def self.add_enclosure_from_url(url, item_maker)
      return unless url

      enclosure = item_maker.enclosure
      content_type = MIME::Types.type_for(File.extname(url).delete('.'))

      enclosure.type = content_type.any? ? content_type.first.to_s : 'application/octet-stream'
      enclosure.length = 0
      enclosure.url = url
    end

    ##
    # @param item
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def self.add_guid(item, item_maker)
      guid = item_maker.guid
      guid.content = Digest::SHA1.hexdigest(item.title)
      guid.isPermaLink = false
    end

    private

    # @return [Html2rss::Config]
    attr_reader :config

    ##
    # @param channel_maker [RSS::Maker::RSS20::Channel]
    # @return nil
    def add_channel(channel_maker)
      %i[language author title description link ttl].each do |attribute_name|
        channel_maker.public_send("#{attribute_name}=", config.public_send(attribute_name))
      end

      channel_maker.generator = "html2rss V. #{::Html2rss::VERSION}"
      channel_maker.lastBuildDate = Time.now
    end

    ##
    # @return [Array<Html2rss::Item>]
    def items
      return @items if defined?(@items)

      items = Item.from_url(config.url, config)

      items.reverse! if config.items_order == :reverse

      @items = items
    end

    ##
    # @param item [Html2rss::Item]
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def add_item(item, item_maker)
      item.available_attributes.each do |attribute_name|
        item_maker.public_send("#{attribute_name}=", item.public_send(attribute_name))
      end

      self.class.add_categories(item.categories, item_maker)
      self.class.add_enclosure_from_url(item.enclosure_url, item_maker) if item.enclosure?
      self.class.add_guid(item, item_maker)
    end
  end
end
