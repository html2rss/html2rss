# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      # Scrapes Schema.org Microdata items embedded directly in HTML markup.
      class Microdata
        include Enumerable

        ITEM_SELECTOR = '[itemscope][itemtype]'
        SUPPORTED_TYPES = (Schema::Thing::SUPPORTED_TYPES | Set['Product']).freeze
        VALUE_ATTRIBUTES = %w[content datetime href src data value].freeze

        def self.options_key = :microdata

        class << self
          def articles?(parsed_body)
            supported_roots(parsed_body).any?
          end

          def supported_roots(parsed_body)
            return [] unless parsed_body

            parsed_body.css(ITEM_SELECTOR).select { supported_root?(_1) }
          end

          def supported_root?(node)
            supported_type_name(node) && top_level_item?(node)
          end

          def supported_type_name(node)
            normalized_types(node['itemtype']).find { SUPPORTED_TYPES.include?(_1) }
          end

          def normalized_types(itemtype)
            itemtype.to_s.split.filter_map do |value|
              type = value.split('/').last.to_s.split('#').last.to_s
              type unless type.empty?
            end
          end

          def top_level_item?(node)
            return false if node.attribute('itemprop')

            node.ancestors.none? { |ancestor| ancestor.attribute('itemscope') && ancestor.attribute('itemprop') }
          end
        end

        ##
        # Builds a Microdata scraper for an already parsed response body.
        #
        # @param parsed_body [Nokogiri::HTML5::Document, Nokogiri::HTML4::Document, Nokogiri::XML::Node, nil]
        #   the parsed response body to inspect for top-level Microdata items.
        # @param url [Html2rss::Url] the absolute page URL used to resolve relative links.
        # @param _opts [Hash] unused scraper-specific options.
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        # @return [void]
        def initialize(parsed_body, url:, **_opts)
          @parsed_body = parsed_body
          @url = url
        end

        ##
        # Iterates over normalized article hashes extracted from supported Microdata roots.
        #
        # @yieldparam article [Hash<Symbol, Object>] the normalized article attributes.
        # @return [Enumerator, void] an enumerator when no block is given.
        def each
          return enum_for(:each) unless block_given?

          self.class.supported_roots(parsed_body).each do |root|
            article = article_from(root)
            yield article if article
          end
        end

        private

        attr_reader :parsed_body, :url

        def article_from(root)
          schema_object = SchemaObjectBuilder.call(root)
          return unless schema_object

          article = Schema::Thing.new(schema_object, url:).call.compact
          return unless valid_article?(article)

          article
        end

        def valid_article?(article)
          return false unless article[:url]

          article[:title] || article[:description]
        end

        # Extracts direct Microdata itemprop values for a single item root.
        module ItemParser
          module_function

          def call(root)
            {}.tap do |properties|
              direct_properties(root).each { append_properties!(properties, _1) }
            end
          end

          def append_properties!(properties, node)
            value = property_value(node)
            return if blank_value?(value)

            property_names(node).each do |name|
              append(properties, name.to_sym, value)
            end
          end

          def direct_properties(root)
            root.css('[itemprop]').select { direct_property?(root, _1) }
          end

          def direct_property?(root, node)
            return false if node == root

            node.ancestors.take_while { _1 != root }.none? { |ancestor| ancestor.attribute('itemscope') }
          end

          def property_names(node)
            node['itemprop'].to_s.split.filter_map do |name|
              stripped = name.strip
              stripped unless stripped.empty?
            end
          end

          def property_value(node)
            value = if node.attribute('itemscope')
                      nested_item(node)
                    else
                      attribute_value(node) || text_value(node)
                    end

            value unless blank_value?(value)
          end

          def nested_item(node)
            item = call(node)
            itemtype = node['itemtype']
            itemid = node['itemid']
            item[:@type] = Microdata.normalized_types(itemtype).first if itemtype
            item[:@id] = itemid if present?(itemid)
            item
          end

          def attribute_value(node)
            VALUE_ATTRIBUTES.each do |attribute|
              value = node[attribute]
              return value if present?(value)
            end

            nil
          end

          def text_value(node)
            value = node.text.to_s.strip
            value unless value.empty?
          end

          def append(properties, key, value)
            return if blank_value?(value)

            unless properties.key?(key)
              properties[key] = value
              return
            end

            properties[key] = Array(properties[key]) << value
          end

          def blank_value?(value)
            case value
            when nil then true
            when String then value.strip.empty?
            when Array, Hash then value.empty?
            else false
            end
          end

          def present?(value)
            !blank_value?(value)
          end
        end
        private_constant :ItemParser

        # Shared value normalization helpers for Microdata property conversion.
        module ValueNormalizer
          module_function

          def url_value(*values)
            values.each do |value|
              candidate = extract_nested_value(value, :url, :@id)
              return candidate.to_s if present?(candidate)
            end

            nil
          end

          def image_value(*values)
            values.each do |value|
              candidate = normalize_image(value)
              return candidate if present?(candidate)
            end

            nil
          end

          def normalize_image(value)
            candidate = unwrap(value)
            return unless present?(candidate)

            return candidate if candidate.is_a?(String) || candidate.is_a?(Hash)

            candidate.to_s
          end

          def normalize_about(value)
            candidate = unwrap(value)
            items = candidate.is_a?(Array) ? candidate : [candidate]
            values = items.filter_map { normalize_about_item(_1) }
            values unless values.empty?
          end

          def normalize_about_item(item)
            case item
            when Hash
              name = item[:name]
              { name: name.to_s } if name
            when String then item
            end
          end

          def string_or_array(value)
            candidate = unwrap(value)
            return unless present?(candidate)

            return stringify(candidate) unless candidate.is_a?(Array)

            result = string_values(candidate)
            result unless result.empty?
          end

          def array_value(*values)
            result = values.flat_map { string_values(Array(unwrap(_1))) }.uniq
            result unless result.empty?
          end

          def string_values(values)
            values.filter_map { stringify(_1) }
          end

          def first_string(*values)
            values.each do |value|
              candidate = stringify(unwrap(value))
              return candidate if present?(candidate)
            end

            nil
          end

          def extract_nested_value(value, *keys)
            candidate = unwrap(value)
            return candidate unless candidate.is_a?(Hash)

            keys.each do |key|
              nested_value = candidate[key]
              return nested_value if present?(nested_value)
            end

            nil
          end

          def unwrap(value)
            value.is_a?(Array) ? value.first : value
          end

          def stringify(value)
            return unless present?(value)
            return value if value.is_a?(String)
            return if value.is_a?(Hash) || value.is_a?(Array)

            value.to_s
          end

          def present?(value)
            case value
            when nil then false
            when String then !value.strip.empty?
            when Array, Hash then !value.empty?
            else true
            end
          end
        end
        private_constant :ValueNormalizer

        # Normalizes raw Microdata properties into the schema-like shape used downstream.
        module SchemaObjectBuilder
          module_function

          extend ValueNormalizer

          def call(root)
            type = Microdata.supported_type_name(root)
            return unless type

            compact_object(type, root, ItemParser.call(root))
          end

          def compact_object(type, root, properties)
            object = base_attributes(type, root, properties)
            merge_categories!(object, properties)
            object.compact
          end

          def base_attributes(type, root, properties)
            identifier = first_string(root['itemid'], properties.delete(:identifier))

            {
              '@type': type,
              '@id': identifier
            }.merge(text_attributes(properties))
              .merge(link_attributes(properties, identifier))
              .merge(media_attributes(properties))
          end

          def title(properties)
            first_string(properties.delete(:headline), properties.delete(:title), properties.delete(:name))
          end

          def text_attributes(properties)
            {
              title: title(properties),
              description: first_string(properties.delete(:description)),
              schema_object_body: first_string(properties.delete(:articleBody)),
              abstract: first_string(properties.delete(:abstract)),
              datePublished: published_at(properties)
            }
          end

          def link_attributes(properties, identifier)
            {
              url: url(properties, identifier)
            }
          end

          def media_attributes(properties)
            {
              image: image_value(properties.delete(:image), properties.delete(:thumbnailUrl))
            }
          end

          def url(properties, fallback_id)
            url_value(
              properties.delete(:url),
              properties.delete(:mainEntityOfPage),
              url_fallback(fallback_id)
            )
          end

          def url_fallback(fallback_id)
            value = first_string(fallback_id)
            return unless value
            return value if value.start_with?('/')
            return value if value.match?(%r{\Ahttps?://})

            nil
          end

          def published_at(properties)
            first_string(
              properties.delete(:datePublished),
              properties.delete(:dateCreated),
              properties.delete(:dateModified),
              properties.delete(:uploadDate)
            )
          end

          def merge_categories!(object, properties)
            categories = array_value(properties.delete(:categories), properties.delete(:articleSection))
            assign_if_present(object, :categories, categories)
            assign_if_present(object, :keywords, string_or_array(properties.delete(:keywords)))
            assign_if_present(object, :tags, string_or_array(properties.delete(:tags)))
            assign_if_present(object, :about, normalize_about(properties.delete(:about)))
          end

          def assign_if_present(object, key, value)
            object[key] = value if value
          end
        end
        private_constant :SchemaObjectBuilder
      end
    end
  end
end
