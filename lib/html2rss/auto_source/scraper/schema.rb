# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scraps articles from Schema.org objects, by looking for the objects in:

      #  1. <script type="application/ld+json"> "schema" tag.
      #  2. tbd
      #
      # See:
      # 1. https://schema.org/NewsArticle
      # 2. https://developers.google.com/search/docs/appearance/structured-data/article#microdata
      class Schema
        TAG_SELECTOR = 'script[type="application/ld+json"]'
        SCHEMA_OBJECT_TYPES = %w[Article NewsArticle].freeze

        class << self
          def articles?(parsed_body)
            parsed_body.css(TAG_SELECTOR).any? { |script| Schema.supported?(script.text) }
          end

          def supported?(script_text)
            SCHEMA_OBJECT_TYPES.any? { |type| script_text.include?("\"@type\":\"#{type}\"") }
          end

          ##
          # Returns a flat array
          # of all supported schema objects
          # by recursively traversing the `from` object.
          #
          # @param object [Hash, Array]
          # @return [Array<Hash>] the schema_objects, or an empty array
          # :reek:DuplicateMethodCall
          def from(object)
            case object
            in Hash if supported_schema_object?(object)
              [object]
            in Hash
              object.values.flat_map { |item| from(item) }.compact
            in Array
              object.flat_map { |item| from(item) }.compact
            else
              []
            end
          end

          def supported_schema_object?(object)
            object_type = object[:@type]
            object_type && SCHEMA_OBJECT_TYPES.include?(object_type)
          end
        end

        def initialize(parsed_body, url:)
          @parsed_body = parsed_body
          @url = url
        end

        ##
        # @return [Array<Hash>] the scraped article_hashes
        def call
          schema_objects.map do |schema_object|
            klass = scraper_from_schema_object(schema_object)
            return nil unless klass

            klass.new(schema_object, url:).call
          end
        end

        private

        def schema_objects
          schema_objects = @parsed_body.css(TAG_SELECTOR).filter_map do |script_tag|
            hash_or_array = JSON.parse(script_tag.text, symbolize_names: true)

            Schema.from(hash_or_array)
          end

          schema_objects.flatten!
          schema_objects
        end

        ##
        # @return [Scraper::Schema::Base, Scraper::Schema::NewsArticle, nil]
        def scraper_from_schema_object(schema_object)
          object_type = schema_object[:@type]

          case object_type
          when 'Article' then Base
          when 'NewsArticle' then NewsArticle
          else
            Log.warn("Schema#scraper_for_type: Unsupported schema object.@type #{object_type}")
            nil
          end
        end

        attr_reader :parsed_body, :url
      end
    end
  end
end
