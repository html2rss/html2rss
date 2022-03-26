# frozen_string_literal: true

require 'mime/types'

module Html2rss
  module RssBuilder
    ##
    # Builds an <item> tag (with the provided maker).
    class Item
      class << self
        ##
        # Adds the item to the Item Maker
        # @param item [Html2rss::Item]
        # @param item_maker [RSS::Maker::RSS20::Items::Item]
        # @param attributes [Set<Symbol>]
        # @return nil
        def add(item, item_maker, attributes)
          attributes.each do |attribute_name|
            item_maker.public_send("#{attribute_name}=", item.public_send(attribute_name))
          end

          add_categories(item, item_maker)
          add_enclosure(item, item_maker)
          add_guid(item, item_maker)
        end

        private

        ##
        # @param item [Html2rss::Item]
        # @param item_maker [RSS::Maker::RSS20::Items::Item]
        # @return nil
        def add_categories(item, item_maker)
          item.categories.each { |category| item_maker.categories.new_category.content = category }
        end

        ##
        # @param item [Html2rss::Item]
        # @param item_maker [RSS::Maker::RSS20::Items::Item]
        # @return nil
        def add_enclosure(item, item_maker)
          return unless item.enclosure?

          item_enclosure = item.enclosure
          rss_enclosure = item_maker.enclosure

          rss_enclosure.type = item_enclosure.type
          rss_enclosure.length = item_enclosure.bits_length
          rss_enclosure.url = item_enclosure.url
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
      end
    end
  end
end
