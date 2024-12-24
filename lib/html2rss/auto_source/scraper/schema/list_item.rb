# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        #
        # @see https://schema.org/ListItem
        class ListItem < Thing
          def id =          (id = (schema_object.dig(:item, :@id) || super).to_s).empty? ? nil : id
          def title =       schema_object.dig(:item, :name) || super || (url ? Utils.titleized_url(url) : nil)
          def description = schema_object.dig(:item, :description) || super

          # @return [Addressable::URI, nil]
          def url
            url = schema_object.dig(:item, :url) || super

            Utils.build_absolute_url_from_relative(url, @url) if url
          end
        end
      end
    end
  end
end
