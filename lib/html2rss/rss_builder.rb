# frozen_string_literal: true

require 'rss'
require 'mime/types'

module Html2rss
  ##
  # Builds the feed, which consists of the '<channel>' and the '<item>'s
  # elements in the RSS.
  class RssBuilder
    private_class_method :new
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def build
      RSS::Maker.make('2.0') do |maker|
        config.stylesheets.each { |stylesheet| add_stylesheet(stylesheet, maker) }

        add_channel(maker.channel)
        items.each { |item| add_item(item, maker.items.new_item) }
      end
    end

    ##
    # @param config [Html2rss::Config]
    # @return [RSS::Rss]
    def self.build(config)
      new(config).build
    end

    private

    ##
    # @param categories [Array<String>]
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def add_categories(categories, item_maker)
      categories.each { |category| item_maker.categories.new_category.content = category }
    end

    ##
    # @param url [String]
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def add_enclosure_from_url(url, item_maker)
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
    def add_guid(item, item_maker)
      guid = item_maker.guid
      guid.content = item.guid
      guid.isPermaLink = false
    end

    ##
    # Adds a stylesheet to the RSS::Maker.
    #
    # @param [Array<Hash>] stylesheet <description>
    # @param [RSS::Maker::RSS20] maker
    # @return nil
    def add_stylesheet(stylesheet, maker)
      maker.xml_stylesheets.new_xml_stylesheet do |xss|
        xss.href = stylesheet[:href]
        xss.type = stylesheet[:type]
        xss.media = stylesheet[:media]
      end
    end

    ##
    # Adds the item to the Item Maker
    # @param item [Html2rss::Item]
    # @param item_maker [RSS::Maker::RSS20::Items::Item]
    # @return nil
    def add_item(item, item_maker)
      item.available_attributes.each do |attribute_name|
        item_maker.public_send("#{attribute_name}=", item.public_send(attribute_name))
      end

      add_categories(item.categories, item_maker)
      add_enclosure_from_url(item.enclosure_url, item_maker) if item.enclosure?
      add_guid(item, item_maker)
    end

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
      Item.from_url(config.url, config).tap do |items|
        items.reverse! if config.items_order == :reverse
      end
    end
  end
end
