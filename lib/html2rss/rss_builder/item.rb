# frozen_string_literal: true

require 'mime/types'

module Html2rss
  module RssBuilder
    ##
    # Builds an <item> tag (with the provided maker).
    class Item
      # Tags which should be processed every time and require non-trivial assignments/treatments.
      SPECIAL_TAGS = %i[categories enclosure guid].freeze

      ##
      # Adds the item to the Item Maker
      #
      # @param maker [RSS::Maker::RSS20::Items::Item]
      # @param item [Html2rss::Item]
      # @param tags [Set<Symbol>]
      # @return nil
      def self.add(maker, item, tags)
        tags.each do |tag|
          next if SPECIAL_TAGS.include?(tag)

          maker.public_send("#{tag}=", item.public_send(tag))
        end

        SPECIAL_TAGS.each do |tag|
          send("add_#{tag}", item, maker)
        end
      end

      ##
      # Adds the <category> tags, if there should be any.
      #
      # @param item [Html2rss::Item]
      # @param maker [RSS::Maker::RSS20::Items::Item]
      # @return nil
      def self.add_categories(item, maker)
        item.categories.each { |category| maker.categories.new_category.content = category }
      end
      private_class_method :add_categories

      ##
      # Adds an enclosure, if there should be one.
      #
      # @param item [Html2rss::Item]
      # @param maker [RSS::Maker::RSS20::Items::Item]
      # @return nil
      def self.add_enclosure(item, maker)
        return unless item.enclosure?

        set_enclosure_attributes(item.enclosure, maker.enclosure)
      end
      private_class_method :add_enclosure

      ##
      # Sets the attributes of an RSS enclosure.
      #
      # @param item_enclosure [Html2rss::Enclosure]
      # @param rss_enclosure [RSS::Maker::RSS20::Items::Enclosure]
      # @return nil
      def self.set_enclosure_attributes(item_enclosure, rss_enclosure)
        rss_enclosure.type = item_enclosure.type
        rss_enclosure.length = item_enclosure.bits_length
        rss_enclosure.url = item_enclosure.url
      end
      private_class_method :set_enclosure_attributes

      ##
      # Adds a non-permalink GUID to the item.
      #
      # @param item [Html2rss::Item]
      # @param maker [RSS::Maker::RSS20::Items::Item]
      # @return nil
      def self.add_guid(item, maker)
        guid = maker.guid
        guid.content = item.guid
        guid.isPermaLink = false
      end
      private_class_method :add_guid
    end
  end
end
