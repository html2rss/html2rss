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

          add_categories(item.categories, item_maker)
          add_enclosure_from_url(item.enclosure_url, item_maker) if item.enclosure?
          add_guid(item, item_maker)
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
      end
    end
  end
end
