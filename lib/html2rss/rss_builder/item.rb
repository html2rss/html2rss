# frozen_string_literal: true

require 'mime/types'

module Html2rss
  module RssBuilder
    ##
    # Builds an <item> tag (with the provided maker).
    class Item
      COMPLEX_TAGS = %i[categories enclosure guid].freeze

      class << self
        ##
        # Adds the item to the Item Maker
        #
        # @param maker [RSS::Maker::RSS20::Items::Item]
        # @param item [Html2rss::Item]
        # @param tags [Set<Symbol>]
        # @return nil
        def add(maker, item, tags)
          (tags - COMPLEX_TAGS).each do |tag|
            maker.public_send("#{tag}=", item.public_send(tag))
          end

          COMPLEX_TAGS.each do |tag|
            send("add_#{tag}", item, maker)
          end
        end

        private

        ##
        # @param item [Html2rss::Item]
        # @param item_maker [RSS::Maker::RSS20::Items::Item]
        # @return nil
        def add_categories(item, maker)
          item.categories.each { |category| maker.categories.new_category.content = category }
        end

        ##
        # @param item [Html2rss::Item]
        # @param item_maker [RSS::Maker::RSS20::Items::Item]
        # @return nil
        def add_enclosure(item, maker)
          return unless item.enclosure?

          item_enclosure = item.enclosure
          rss_enclosure = maker.enclosure

          rss_enclosure.type = item_enclosure.type
          rss_enclosure.length = item_enclosure.bits_length
          rss_enclosure.url = item_enclosure.url
        end

        ##
        # @param item
        # @param item_maker [RSS::Maker::RSS20::Items::Item]
        # @return nil
        def add_guid(item, maker)
          guid = maker.guid
          guid.content = item.guid
          guid.isPermaLink = false
        end
      end
    end
  end
end
