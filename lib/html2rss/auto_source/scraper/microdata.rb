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
        CATEGORY_FIELDS = %i[keywords categories tags].freeze

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

        def initialize(parsed_body, url:, **_opts)
          @parsed_body = parsed_body
          @url = url
        end

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
          return if article[:url].nil?
          return if article[:title].nil? && article[:description].nil?

          article
        end

        module ItemParser
          module_function

          def call(root)
            direct_properties(root).each_with_object({}) do |node, properties|
              property_names(node).each do |name|
                append(properties, name.to_sym, property_value(node))
              end
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
            item[:@type] = Microdata.normalized_types(node['itemtype']).first if node['itemtype']
            item[:@id] = node['itemid'] if present?(node['itemid'])
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

            if properties.key?(key)
              properties[key] = Array(properties[key]) << value
            else
              properties[key] = value
            end
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

        module SchemaObjectBuilder
          module_function

          def call(root)
            type = Microdata.supported_type_name(root)
            return unless type

            properties = ItemParser.call(root)
            object = { '@type': type }
            object[:@id] = first_string(root['itemid'], properties.delete(:identifier))
            object[:title] = first_string(properties.delete(:headline), properties.delete(:title), properties.delete(:name))
            object[:url] = url_value(properties.delete(:url), properties.delete(:mainEntityOfPage), object[:@id])
            object[:description] = first_string(properties.delete(:description))
            object[:schema_object_body] = first_string(properties.delete(:articleBody))
            object[:abstract] = first_string(properties.delete(:abstract))
            object[:image] = image_value(properties.delete(:image), properties.delete(:thumbnailUrl))
            object[:datePublished] = first_string(
              properties.delete(:datePublished),
              properties.delete(:dateCreated),
              properties.delete(:dateModified),
              properties.delete(:uploadDate)
            )
            merge_categories!(object, properties)
            object.compact
          end

          def merge_categories!(object, properties)
            categories = array_value(properties.delete(:categories), properties.delete(:articleSection))
            object[:categories] = categories if categories

            keywords = string_or_array(properties.delete(:keywords))
            object[:keywords] = keywords if keywords

            tags = string_or_array(properties.delete(:tags))
            object[:tags] = tags if tags

            about = normalize_about(properties.delete(:about))
            object[:about] = about if about
          end

          def url_value(*values)
            value = values.lazy.map { extract_nested_value(_1, :url, :@id) }.find { present?(_1) }
            value.to_s if present?(value)
          end

          def image_value(*values)
            values.lazy.map { normalize_image(_1) }.find { present?(_1) }
          end

          def normalize_image(value)
            candidate = unwrap(value)
            return unless present?(candidate)

            return candidate if candidate.is_a?(String)
            return candidate if candidate.is_a?(Hash)

            candidate.to_s
          end

          def normalize_about(value)
            candidate = unwrap(value)
            items = candidate.is_a?(Array) ? candidate : [candidate]

            values = items.filter_map do |item|
              case item
              when Hash then item[:name] ? { name: item[:name].to_s } : nil
              when String then item
              end
            end

            values unless values.empty?
          end

          def string_or_array(value)
            candidate = unwrap(value)
            return unless present?(candidate)

            if candidate.is_a?(Array)
              result = candidate.filter_map { stringify(_1) }
              result unless result.empty?
            else
              stringify(candidate)
            end
          end

          def array_value(*values)
            result = values.flat_map do |value|
              candidate = unwrap(value)
              Array(candidate).filter_map { stringify(_1) }
            end

            result.uniq!
            result unless result.empty?
          end

          def first_string(*values)
            values.lazy.map { stringify(unwrap(_1)) }.find { present?(_1) }
          end

          def extract_nested_value(value, *keys)
            candidate = unwrap(value)
            return candidate unless candidate.is_a?(Hash)

            keys.each do |key|
              return candidate[key] if present?(candidate[key])
            end

            nil
          end

          def unwrap(value)
            value.is_a?(Array) ? value.first : value
          end

          def stringify(value)
            return unless present?(value)
            return value.to_s if value.is_a?(String)
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
        private_constant :SchemaObjectBuilder
      end
    end
  end
end
