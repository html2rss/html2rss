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

        # Matches a leading schema.org URL prefix on @type values (http or https).
        SCHEMA_ORG_PREFIX_RE = %r{\Ahttps?://schema\.org/}i

        # Container types that must never be emitted as feed items (walk children only).
        DENIED_CONTAINER_TYPES = Set[
          'ItemList', 'Blog', 'BreadcrumbList', 'WebPage', 'CollectionPage'
        ].freeze

        # Canonical Schema.org type names keyed by folded wire forms (case-insensitive lookup).
        CANONICAL_BY_DOWNCASE = begin
          canonical_types = Thing::SUPPORTED_TYPES | ItemList::SUPPORTED_TYPES | DENIED_CONTAINER_TYPES | Set['Product']
          canonical_types.to_h { |type| [::Html2rss::Html::Probe.fold(type), type] }.freeze
        end.freeze

        # Pre-compiled regex for supported schema types (short name or schema.org URL; string or array @type).
        # Allows preceding entries in a JSON @type array (e.g. ["WebPage","NewsArticle"]).
        SUPPORTED_TYPES_RE = begin
          types = Thing::SUPPORTED_TYPES | ItemList::SUPPORTED_TYPES
          type_re = Regexp.union(types.to_a)
          %r{(?i)"@type"\s*:\s*(?:\[\s*(?:"[^"]*"\s*,\s*)*)?"(?:https?://schema\.org/)?(?:#{type_re.source})"}
        end.freeze

        # Prefer these keys when recursively walking unsupported container objects.
        COLLECTION_KEYS = %i[itemListElement blogPost mainEntity hasPart].freeze

        # @return [Symbol] scraper config key
        def self.options_key = :schema

        class << self
          # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
          # @return [Boolean] whether the page includes supported schema types
          def articles?(parsed_body)
            ::Html2rss::Html::Probe.scripts(parsed_body, ::Html2rss::Html::Probe::APPLICATION_LD_JSON)
                                   .any? { |script| supported_schema_type?(script) }
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
          # Prefers collection keys ({COLLECTION_KEYS}) when walking containers.
          #
          # @param object [Hash, Array, Nokogiri::XML::Element]
          # @return [Array<Hash>] the schema_objects, or an empty array
          # :reek:DuplicateMethodCall
          def from(object)
            case object
            when Nokogiri::XML::Element then from(parse_script_tag(object))
            when Hash then from_hash(object)
            when Array then object.flat_map { |item| from(item) }
            else []
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

            # Prefer article/list extractors over denied containers for multi-type @type arrays
            # (e.g. ["NewsArticle","WebPage"]).
            return ItemList if types.intersect?(ItemList::SUPPORTED_TYPES)
            return Thing if types.intersect?(Thing::SUPPORTED_TYPES)
            return nil if types.intersect?(DENIED_CONTAINER_TYPES)

            Log.debug("#{name}: unsupported schema object @type=#{schema_object[:@type].inspect}")
            nil
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
              return Set.new if short.empty?

              canonical = CANONICAL_BY_DOWNCASE.fetch(::Html2rss::Html::Probe.fold(short), short)
              Set[canonical]
            else
              Set.new
            end
          end

          private

          # @param hash [Hash] candidate schema object
          # @return [Array<Hash>] the object itself or nested supported objects
          def from_hash(hash)
            supported_schema_object?(hash) ? [hash] : walk_hash_values(hash)
          end

          # @param hash [Hash] schema object that is not itself extractable
          # @return [Array<Hash>] nested supported objects
          def walk_hash_values(hash)
            preferred = COLLECTION_KEYS.filter_map { |key| hash[key] }
            rest = hash.except(*COLLECTION_KEYS).values
            (preferred + rest).flat_map { |item| from(item) }
          end

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
          ::Html2rss::Html::Probe.scripts(@parsed_body, ::Html2rss::Html::Probe::APPLICATION_LD_JSON)
                                 .flat_map { |tag| Schema.from(tag) }
        end

        attr_reader :parsed_body, :url
      end
    end
  end
end
