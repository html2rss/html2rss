# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class Schema
        ##
        # Extracts categories from Schema.org structured data.
        module CategoryExtractor
          # Schema.org fields checked for category-like string values.
          CATEGORY_FIELDS = %i[articleSection keywords categories tags].freeze

          ##
          # @param schema_object [Hash] The schema object
          # @return [Array<String>] Array of category strings
          def self.call(schema_object)
            Set.new.tap do |categories|
              CATEGORY_FIELDS.each { |field| add_field(categories, schema_object[field]) }
              add_about(categories, schema_object[:about])
            end.to_a
          end

          class << self
            private

            def add_field(categories, value)
              case value
              when Array
                value.each { |item| add_string(categories, item.to_s) }
              when String
                split_string(categories, value)
              end
            end

            def add_about(categories, about)
              case about
              when Array then add_about_items(categories, about)
              when String then split_string(categories, about)
              end
            end

            def add_about_items(categories, about)
              about.each do |item|
                case item
                when Hash then add_string(categories, item[:name].to_s)
                when String then add_string(categories, item)
                end
              end
            end

            def split_string(categories, string)
              string.split(/[,;|]/).each { |part| add_string(categories, part.strip) }
            end

            def add_string(categories, string)
              categories.add(string) unless string.empty?
            end
          end
        end
      end
    end
  end
end
