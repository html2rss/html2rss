# frozen_string_literal: true

require 'rss'

module Html2rss
  ##
  # Builds the RSS 2.0 feed, which consists of the '<channel>' and the '<item>'s
  # tags in the RSS.
  module RssBuilder
    ##
    # Possible tags inside a RSS 2.0 <channel> tag.
    CHANNEL_ATTRIBUTES = %i[language author title description link ttl].freeze

    ##
    # @param config [Html2rss::Config]
    # @return [RSS::Rss]
    def self.build(config)
      RSS::Maker.make('2.0') do |maker|
        Stylesheet.add(maker, config.stylesheets)
        Channel.add(maker.channel, config, CHANNEL_ATTRIBUTES)

        item_attributes = item_attributes(config)
        Html2rss::Item.from_url(config.url, config)
                      .tap { |items| items.reverse! if config.items_order == :reverse }
                      .each do |item|
          Item.add(item, maker.items.new_item, item_attributes)
        end
      end
    end

    def self.item_attributes(config)
      (%i[title link description author comments updated] & config.attribute_names) - %i[categories enclosure]
    end
  end
end
