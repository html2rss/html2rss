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
    # @param config [Html2rss::Config]
    # @return [RSS::Rss]
    def self.build(config)
      # request from config.url, keep the request/response, pass down to item/channel builders
      RSS::Maker.make('2.0') do |maker|
        Stylesheet.add(maker, config.stylesheets)

        Channel.add(config, maker.channel, CHANNEL_TAGS)

        item_attributes = config.attribute_names & ITEM_TAGS
        Html2rss::Item.from_url(config.url, config)
                      .tap { |items| items.reverse! if config.items_order == :reverse }
                      .each do |item|
          Item.add(maker.items.new_item, item, item_attributes)
        end
      end
    end
  end
end
