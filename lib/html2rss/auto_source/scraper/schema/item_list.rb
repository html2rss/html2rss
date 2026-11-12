# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        # Walks schema.org ItemList objects and yields article-shaped elements only.
        # The ItemList container itself is never emitted.
        #
        # @see https://schema.org/ItemList
        class ItemList < Thing
          # Schema.org type names handled by the ItemList extractor.
          SUPPORTED_TYPES = Set['ItemList']

          # @return [Array<Hash>] article hashes from list elements (no parent container)
          def call
            elements = @schema_object[:itemListElement]
            return [] unless elements

            elements = [elements] unless elements.is_a?(Array)
            elements.filter_map { |element| materialize_element(element) }
          end

          private

          # @param element [Object] raw itemListElement entry
          # @return [Hash, nil] scraped article hash when emit-worthy
          def materialize_element(element)
            object, from_list_item = unwrap_list_item(element)
            return unless object.is_a?(Hash)
            return unless emit?(object, from_list_item:)

            # Leave empty titles empty — do not invent from URL path (Cleanup allows nil).
            item = Thing.new(object, url: base_url || '').call
            media?(object) ? item.merge(media: true) : item
          end

          # @param object [Hash] schema object
          # @return [Boolean] whether the object is an audio/video object, which must not count as an article
          def media?(object)
            Schema.normalize_types(object[:@type]).intersect?(Thing::MEDIA_TYPES)
          end

          # @param element [Object] raw list entry
          # @return [Array(Hash, Boolean)] schema object and whether it came from ListItem
          def unwrap_list_item(element)
            return [element, false] unless element.is_a?(Hash)

            types = Schema.normalize_types(element[:@type])
            return [element, false] unless types.include?('ListItem')

            item = element[:item]
            [item.is_a?(Hash) ? item : element, true]
          end

          # @param object [Hash] candidate schema object
          # @param from_list_item [Boolean] whether object came from a ListItem unwrap
          # @return [Boolean] whether to emit this object: a ListItem unwrap admits everything except pure
          #   entities ({Thing::ENTITY_TYPES}); a bare element must be an article, Event, JobPosting or media type
          def emit?(object, from_list_item:)
            types = Schema.normalize_types(object[:@type])
            return types.empty? || !types.subset?(Thing::ENTITY_TYPES) if from_list_item

            types.intersect?(Thing::SUPPORTED_TYPES | Thing::ITEM_LIST_TYPES)
          end
        end
      end
    end
  end
end
