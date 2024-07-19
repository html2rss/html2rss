# frozen_string_literal: true

require 'rss'

module Html2rss
  ##
  # Builds the RSS 2.0 feed, which consists of the '<channel>' and the '<item>'s
  # tags in the RSS.
  module RssBuilder
    # Possible tags inside a RSS 2.0 <channel> tag.
    CHANNEL_TAGS = %i[language author title description link ttl].freeze
    # Possible tags inside a RSS 2.0 <item> tag.
    ITEM_TAGS = %i[title link description author comments updated].freeze

    ##
    # Builds an RSS 2.0 feed based on the provided configuration.
    #
    # @param config [Html2rss::Config] Configuration object containing feed details.
    # @return [RSS::Rss] RSS feed object.
    def self.build(config)
      RSS::Maker.make('2.0') do |maker|
        add_stylesheets(maker, config.stylesheets)
        add_channel(maker, config)
        add_items(maker, config)
      end
    end

    ##
    # Adds stylesheets to the RSS maker.
    #
    # @param maker [RSS::Maker] RSS maker instance.
    # @param stylesheets [Array<String>] Array of stylesheets to add.
    def self.add_stylesheets(maker, stylesheets)
      Stylesheet.add(maker, stylesheets)
    end

    ##
    # Adds channel information to the RSS maker.
    #
    # @param maker [RSS::Maker] RSS maker instance.
    # @param config [Html2rss::Config] Configuration object containing feed details.
    def self.add_channel(maker, config)
      channel = maker.channel
      CHANNEL_TAGS.each do |tag|
        Channel.add(channel, config, [tag])
      end
    end

    ##
    # Adds items to the RSS maker based on configuration.
    #
    # @param maker [RSS::Maker] RSS maker instance.
    # @param config [Html2rss::Config] Configuration object containing feed details.
    def self.add_items(maker, config)
      item_attributes = extract_item_attributes(config)
      items = fetch_items(config)
      items.reverse! if config.items_order == :reverse

      items.each do |item|
        add_item(maker, item, item_attributes)
      end
    end

    ##
    # Adds a single item to the RSS maker.
    #
    # @param maker [RSS::Maker] RSS maker instance.
    # @param item [Html2rss::Item] Item to add.
    # @param item_attributes [Array<Symbol>] Array of item attributes.
    # @return [nil]
    def self.add_item(maker, item, item_attributes)
      new_item = maker.items.new_item
      Item.add(new_item, item, item_attributes)
    end

    ##
    # Extracts item attributes from configuration.
    #
    # @param config [Html2rss::Config] Configuration object containing feed details.
    # @return [Array<Symbol>] Array of item attributes.
    def self.extract_item_attributes(config)
      config.item_selector_names & ITEM_TAGS
    end

    ##
    # Fetches items from the URL specified in configuration.
    #
    # @param config [Html2rss::Config] Configuration object containing feed details.
    # @return [Array<Html2rss::Item>] Array of items.
    def self.fetch_items(config)
      Html2rss::Item.from_url(config.url, config)
    end

    private_class_method :extract_item_attributes, :fetch_items, :add_item
  end
end
