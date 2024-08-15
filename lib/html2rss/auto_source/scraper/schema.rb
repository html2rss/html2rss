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
        include Enumerable

        TAG_SELECTOR = 'script[type="application/ld+json"]'
        SCHEMA_OBJECT_TYPES = %w[Article NewsArticle].freeze

        class << self
          def articles?(parsed_body)
            parsed_body.css(TAG_SELECTOR).any? do |script|
              SCHEMA_OBJECT_TYPES.any? { |type| script.text.match?(/"@type"\s*:\s*"#{Regexp.escape(type)}"/) }
            end
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
            when Nokogiri::XML::Element
              from(parse_script_tag(object))
            when Hash
              supported_schema_object?(object) ? [object] : object.values.flat_map { |item| from(item) }
            when Array
              object.flat_map { |item| from(item) }
            else
              []
            end
          end

          def supported_schema_object?(object)
            scraper_for_schema_object(object) ? true : false
          end

          ##
          # @return [Scraper::Schema::Base, Scraper::Schema::NewsArticle, nil]
          def scraper_for_schema_object(schema_object)
            case schema_object[:@type]
            when 'Article' then Base
            when 'NewsArticle' then NewsArticle
            else
              Log.warn("Schema#scraper_for_schema_object: Unsupported schema object @type: #{schema_object[:@type]}")
              nil
            end
          end

          private

          def parse_script_tag(script_tag)
            JSON.parse(script_tag.text, symbolize_names: true)
          rescue JSON::ParserError => error
            Log.warn('Schema#schema_objects: Failed to parse JSON', error: error.message)
            []
          end
        end

        def initialize(parsed_body, url:)
          @parsed_body = parsed_body
          @url = url
        end

        ##
        # @yield [Hash] Each scraped article_hash
        # @return [Array<Hash>] the scraped article_hashes
        def each(&)
          schema_objects.filter_map do |schema_object|
            next unless (klass = self.class.scraper_for_schema_object(schema_object))
            next unless (article_hash = klass.new(schema_object, url:).call)

            article_hash[:generated_by] = klass

            yield article_hash

            article_hash
          end
        end

        private

        def schema_objects
          @parsed_body.css(TAG_SELECTOR).flat_map do |tag|
            Schema.from(tag)
          end
        end

        attr_reader :parsed_body, :url
      end
    end
  end
end
