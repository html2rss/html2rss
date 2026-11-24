# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      # Scrapes Schema.org Microdata items embedded directly in HTML markup.
      class Microdata < Base
        # Selector matching nodes that define a microdata item scope.
        ITEM_SELECTOR = '[itemscope][itemtype]'
        # Schema.org types supported for article extraction via Microdata.
        SUPPORTED_TYPES = (Schema::Thing::SUPPORTED_TYPES | Set['Product']).freeze
        # Attribute names checked first for microdata property values.
        VALUE_ATTRIBUTES = %w[content datetime href src data value].freeze
        # Text properties handed to {Schema::Thing} as one string; its own precedence picks among them.
        TEXT_KEYS = %i[description articleBody abstract datePublished dateCreated dateModified uploadDate].freeze
        # Properties handed to {Schema::Thing} unchanged.
        PASS_KEYS = %i[author publisher video audio associatedMedia].freeze
        # Image properties, in precedence order; the first present one is the only candidate.
        IMAGE_KEYS = %i[image thumbnailUrl thumbnail].freeze

        # @return [Symbol] scraper config key
        def self.options_key = :microdata

        ##
        # @param _opts [Hash] unused options
        # @return [Integer]
        def self.request_slots(_opts = {}) = 0

        class << self
          # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
          # @return [Boolean] whether any supported Microdata root exists
          def articles?(parsed_body)
            supported_roots(parsed_body).any?
          end

          # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
          # @return [Array<Nokogiri::XML::Element>] top-level supported Microdata roots
          def supported_roots(parsed_body)
            return [] unless parsed_body

            parsed_body.css(ITEM_SELECTOR).select { supported_root?(_1) }
          end

          # @param node [Nokogiri::XML::Element] itemscope candidate node
          # @return [Boolean] whether the node is a supported top-level root
          def supported_root?(node)
            supported_type_name(node) && top_level_item?(node)
          end

          # @param node [Nokogiri::XML::Element] itemscope candidate node
          # @return [String, nil] supported schema type name when present
          def supported_type_name(node)
            itemtype_type_names(node['itemtype']).find { SUPPORTED_TYPES.include?(_1) }
          end

          # @param itemtype [String, nil] raw itemtype attribute value
          # @return [Array<String>] canonical schema type names
          def itemtype_type_names(itemtype)
            itemtype.to_s.split.filter_map do |value|
              short = value.split('/').last.to_s.split('#').last.to_s
              next if short.empty?

              Schema.canonicalize_type(short)
            end
          end

          # @param node [Nokogiri::XML::Element] itemscope candidate node
          # @return [Boolean] whether the node is not nested in another item property
          def top_level_item?(node)
            return false if node.attribute('itemprop')

            curr = node.parent
            while curr && !curr.document? && curr.name != 'html'
              return false if curr.attribute('itemscope') && curr.attribute('itemprop')

              curr = curr.parent
            end
            true
          end
        end

        ##
        # Iterates over normalized article hashes extracted from supported Microdata roots.
        #
        # @yieldparam article [Hash{Symbol => Object}] the normalized article attributes.
        # @return [Enumerator, void] an enumerator when no block is given.
        def each
          return enum_for(:each) unless block_given?

          self.class.supported_roots(parsed_body).each do |root|
            article = article_from(root)
            yield article if article
          end
        end

        private

        # @param root [Nokogiri::XML::Element] supported Microdata root node
        # @return [Hash{Symbol => Object, nil}] normalized article hash
        def article_from(root)
          schema_object = SchemaObject.call(root)
          article = Schema::Thing.new(schema_object, url:).call.compact
          return unless valid_article?(article)

          article
        end

        # @param article [Hash{Symbol => Object}] normalized article hash
        # @return [Boolean] whether article contains required fields
        def valid_article?(article)
          return false unless article[:url]

          article[:title] || article[:description]
        end

        # Extracts direct Microdata itemprop values for a single item root.
        module ItemParser
          class << self
            # @param root [Nokogiri::XML::Element] microdata root node
            # @return [Hash{Symbol => Object}] extracted direct properties
            def call(root)
              {}.tap do |properties|
                direct_properties(root).each { append_properties!(properties, _1) }
              end
            end

            # @param properties [Hash{Symbol => Object}] accumulator hash for parsed properties
            # @param node [Nokogiri::XML::Element] itemprop node
            # @return [void]
            def append_properties!(properties, node)
              value = property_value(node)
              return if blank_value?(value)

              property_names(node).each do |name|
                append(properties, name.to_sym, value)
              end
            end

            # @param root [Nokogiri::XML::Element] microdata root node
            # @return [Array<Nokogiri::XML::Element>] direct property nodes for the root
            def direct_properties(root)
              root.css('[itemprop]').select { direct_property?(root, _1) }
            end

            # @param root [Nokogiri::XML::Element] microdata root node
            # @param node [Nokogiri::XML::Element] candidate itemprop node
            # @return [Boolean] whether the node belongs directly to the current root item
            def direct_property?(root, node)
              curr = node.parent
              while curr && curr != root
                return false if curr.attribute('itemscope')

                curr = curr.parent
              end
              true
            end

            # @param node [Nokogiri::XML::Element] itemprop node
            # @return [Array<String>] normalized property names
            def property_names(node)
              node['itemprop'].to_s.split.filter_map do |name|
                stripped = name.strip
                stripped unless stripped.empty?
              end
            end

            # @param node [Nokogiri::XML::Element] itemprop node
            # @return [Object, nil] parsed property value
            def property_value(node)
              value = if node.attribute('itemscope')
                        nested_item(node)
                      else
                        attribute_value(node) || text_value(node)
                      end

              value unless blank_value?(value)
            end

            # @param node [Nokogiri::XML::Element] nested itemscope node
            # @return [Hash{Symbol => Object}] nested parsed microdata item
            def nested_item(node)
              item = call(node)
              itemtype = node['itemtype']
              itemid = node['itemid']
              item[:@type] = Microdata.itemtype_type_names(itemtype).first if itemtype
              item[:@id] = itemid if present?(itemid)
              item
            end

            # @param node [Nokogiri::XML::Element] itemprop node
            # @return [String, nil] first present attribute value
            def attribute_value(node)
              VALUE_ATTRIBUTES.each do |attribute|
                value = node[attribute]
                return value if present?(value)
              end

              nil
            end

            # @param node [Nokogiri::XML::Element] itemprop node
            # @return [String, nil] normalized text content
            def text_value(node)
              value = node.text.to_s.strip
              value unless value.empty?
            end

            # @param properties [Hash{Symbol => Object}] accumulator hash for parsed properties
            # @param key [Symbol] target property key
            # @param value [Object] parsed property value to assign for the key
            # @return [void]
            def append(properties, key, value)
              return if blank_value?(value)

              unless properties.key?(key)
                properties[key] = value
                return
              end

              existing = properties[key]
              properties[key] = existing.is_a?(Array) ? existing + [value] : [existing, value]
            end

            # @param value [Object] candidate value
            # @return [Boolean] whether value is blank for microdata extraction purposes
            def blank_value?(value)
              case value
              when nil then true
              when String then value.strip.empty?
              when Array, Hash then value.empty?
              else false
              end
            end

            # @param value [Object] candidate value
            # @return [Boolean] whether value is present for microdata extraction purposes
            def present?(value)
              !blank_value?(value)
            end
          end
        end
        private_constant :ItemParser

        # Maps parsed Microdata properties onto the keys {Schema::Thing} reads, which then resolves every field.
        # Only values Thing would read differently are shaped here: one text value per field (a nested item or
        # list tail is none), title precedence (headline, title, name), one image, a relative or `itemid` url,
        # and `articleSection` filed under `categories`.
        module SchemaObject
          class << self
            # @param root [Nokogiri::XML::Element] supported microdata root node
            # @return [Hash{Symbol => Object}] schema-like object
            def call(root)
              props = ItemParser.call(root)
              id = text(root['itemid'], props[:identifier])
              base(props, id).merge(lists(props), TEXT_KEYS.to_h { [_1, text(props[_1])] }, props.slice(*PASS_KEYS))
            end

            # @param props [Hash{Symbol => Object}] parsed properties
            # @param id [String, nil] item identifier
            # @return [Hash{Symbol => Object}] identity, title, url and image
            def base(props, id)
              { '@id': id, headline: text(*props.values_at(:headline, :title, :name)),
                url: url_value(props, id), image: first_value(props.values_at(*IMAGE_KEYS).compact) }
            end

            # @param props [Hash{Symbol => Object}] parsed properties
            # @return [Hash{Symbol => Object}] category-like lists of strings
            def lists(props)
              { categories: strings(props[:categories], props[:articleSection]),
                keywords: strings(props[:keywords]), tags: strings(props[:tags]),
                about: props[:about].is_a?(Array) ? props[:about] : [props[:about]].compact }
            end

            # @param values [Array<Object>] candidates, scalar or list
            # @return [String, nil] the first candidate's first value when it is a string (a nested item is none)
            def text(*values)
              values.each do |value|
                value = value.first if value.is_a?(Array)
                return value if value.is_a?(String)
              end

              nil
            end

            # @param values [Array<Object>] candidates, scalar or list
            # @return [Array<String>] every string among them (nested items are dropped)
            def strings(*values)
              values.flat_map { _1.is_a?(Array) ? _1 : [_1] }.grep(String)
            end

            # @param values [Array<Object>] candidates, scalar or list
            # @return [Object, nil] the first candidate's first value
            def first_value(values)
              values.first.then { _1.is_a?(Array) ? _1.first : _1 }
            end

            # @param props [Hash{Symbol => Object}] parsed properties
            # @param id [String, nil] item identifier
            # @return [String, nil] first of `url`, `mainEntityOfPage` (or its url or id), a root-relative id
            def url_value(props, id)
              url_like = id if id&.start_with?('/')
              [props[:url], props[:mainEntityOfPage], url_like].each do |value|
                value = first_value([value])
                value = value.values_at(:url, :@id).compact.first if value.is_a?(Hash)
                return value if value
              end

              nil
            end
          end
        end
        private_constant :SchemaObject
      end
    end
  end
end
