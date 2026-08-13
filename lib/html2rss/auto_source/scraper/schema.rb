# frozen_string_literal: true

require 'json'
require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes articles from Schema.org objects, by looking for the objects in:
      # <script type="application/ld+json"> "schema" tags.
      #
      # @see https://schema.org/docs/full.html
      # @see https://developers.google.com/search/docs/appearance/structured-data/article#microdata
      class Schema
        include Enumerable

        # Selector for JSON-LD script tags containing Schema.org objects.
        TAG_SELECTOR = 'script[type="application/ld+json"]'

        # Pre-compiled regex for supported schema types (short name or schema.org URL; string or array @type).
        SUPPORTED_TYPES_RE = begin
          types = Thing::SUPPORTED_TYPES | ItemList::SUPPORTED_TYPES
          type_re = Regexp.union(types.to_a)
          %r{"@type"\s*:\s*(?:\[\s*)?"(?:https?://schema\.org/)?(?:#{type_re.source})"}
        end.freeze

        SCHEMA_ORG_PREFIX_RE = %r{\Ahttps?://schema\.org/}i

        # @return [Symbol] scraper config key
        def self.options_key = :schema

        class << self
          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @return [Boolean] whether the page includes supported schema types
          def articles?(parsed_body)
            parsed_body.css(TAG_SELECTOR).any? { |script| supported_schema_type?(script) }
          end

          # @param script [Nokogiri::XML::Element] schema JSON-LD script tag
          # @return [Boolean] whether the tag references a supported schema type
          def supported_schema_type?(script)
            script.text.match?(SUPPORTED_TYPES_RE)
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

          # @param object [Hash{Symbol => Object}] schema candidate object
          # @return [Boolean] whether an extractor exists for the candidate object
          def supported_schema_object?(object)
            scraper_for_schema_object(object) ? true : false
          end

          ##
          # @param schema_object [Hash{Symbol => Object}] schema object with an @type key
          # @return [Scraper::Schema::Thing, Scraper::Schema::ItemList, nil] a class responding to `#call`
          def scraper_for_schema_object(schema_object)
            types = normalize_types(schema_object[:@type])

            if types.intersect?(Thing::SUPPORTED_TYPES)
              Thing
            elsif types.intersect?(ItemList::SUPPORTED_TYPES)
              ItemList
            else
              Log.debug("#{name}: unsupported schema object @type=#{schema_object[:@type].inspect}")
              nil
            end
          end

          # Normalizes Schema.org `@type` wire forms to short type names.
          #
          # Handles String, Symbol, Array, and strips `https://schema.org/` / `http://schema.org/` prefixes.
          #
          # @param object [String, Symbol, Array, nil] raw `@type` value
          # @return [Set<String>] short type names (e.g. "NewsArticle")
          # @api private
          def normalize_types(object)
            case object
            when Array
              object.each_with_object(Set.new) { |item, set| set.merge(normalize_types(item)) }
            when String, Symbol
              short = object.to_s.sub(SCHEMA_ORG_PREFIX_RE, '')
              short.empty? ? Set.new : Set[short]
            else
              Set.new
            end
          end

          private

          def parse_script_tag(script_tag)
            JSON.parse(script_tag.text, symbolize_names: true)
          rescue JSON::ParserError => error
            Log.warn("#{name}: failed to parse JSON", error: error.message)
            []
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base page URL
        # @param opts [Hash] scraper-specific options
        # @option opts [Object] :_reserved reserved for future scraper-specific options
        def initialize(parsed_body, url:, **opts)
          @parsed_body = parsed_body
          @url = url
          @opts = opts
        end

        ##
        # @yield [Hash] Each scraped article_hash
        # @return [Array<Hash>] the scraped article_hashes
        def each(&)
          return enum_for(:each) unless block_given?

          schema_objects.filter_map do |schema_object|
            next unless (klass = self.class.scraper_for_schema_object(schema_object))
            next unless (results = klass.new(schema_object, url:).call)

            if results.is_a?(Array)
              results.each { |result| yield(result) } # rubocop:disable Style/ExplicitBlockArgument
            else
              yield(results)
            end
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
