# frozen_string_literal: true

require 'json'
require 'nokogiri'
require 'set'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes articles from Schema.org objects, by looking for the objects in:

      # <script type="application/ld+json"> "schema" tags.
      #
      # See:
      # 1. https://schema.org/docs/full.html
      # 2. https://developers.google.com/search/docs/appearance/structured-data/article#microdata
      class Schema
        include Enumerable

        TAG_SELECTOR = 'script[type="application/ld+json"]'

        class << self
          def articles?(parsed_body)
            parsed_body.css(TAG_SELECTOR).any? do |script|
              (Thing::SUPPORTED_TYPES | ItemList::SUPPORTED_TYPES).any? do |type|
                script.text.match?(/"@type"\s*:\s*"#{Regexp.escape(type)}"/)
              end
            end
          end

          ##
          # Returns a flat array
          # of all supported schema objects
          # by recursively traversing the given `object`.
          #
          # @param object [Hash, Array, Nokogiri::XML::Element]
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
          # @return [Scraper::Schema::Thing, Scraper::Schema::ItemList, nil] a class responding to `#call`
          def scraper_for_schema_object(schema_object)
            type = schema_object[:@type]

            if Thing::SUPPORTED_TYPES.member?(type)
              Thing
            elsif ItemList::SUPPORTED_TYPES.member?(type)
              ItemList
            else
              Log.warn("Schema#scraper_for_schema_object: Unsupported schema object @type: #{type}")
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
          return enum_for(:each) unless block_given?

          schema_objects.filter_map do |schema_object|
            next unless (klass = self.class.scraper_for_schema_object(schema_object))
            next unless (results = klass.new(schema_object, url:).call)

            results.is_a?(Array) ? results.each(&) : yield(results)
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
