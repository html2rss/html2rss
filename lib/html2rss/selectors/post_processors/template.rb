# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      ##
      # Returns a formatted String according to the string pattern.
      # It uses [Kernel#format](https://ruby-doc.org/core/Kernel.html#method-i-format)
      #
      # It supports the format pattern `%<key>s` and `%{key}`, where `key` is the key of the selector.
      # If `%{self}` is used, the selectors extracted value will be used.
      #
      # Imagine this HTML:
      #
      #    <li>
      #      <h1>Product</h1>
      #      <span class="price">23,42€</span>
      #    </li>
      #
      #
      # YAML usage example:
      #
      #    selectors:
      #      items:
      #        selector: 'li'
      #      price:
      #        selector: '.price'
      #      title:
      #        selector: h1
      #        post_process:
      #          name: template
      #          string: '`%{self}` (`%{price}`)'
      #
      # Would return:
      #    'Product (23,42€)'
      class Template < Base
        # Expected Ruby class for the extracted value before this post-processor runs.
        VALUE_TYPE = String

        # Config-facing options contract (validator / SchemaDoc / Base.validate_options!).
        OPTIONS = [
          Option.new(name: :string, type: String)
        ].freeze

        # JSON Schema description exported via +schema_doc+.
        # rubocop:disable Style/FormatStringToken -- documents Kernel#format `%{key}` placeholders
        DESCRIPTION = 'Format a string with Kernel#format-style placeholders (`%{key}` / `%<key>s`). ' \
                      '`%{self}` is the current selector value; other keys resolve sibling selectors.'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'template', 'string' => '`%{self}` (`%{price}`)' }
        ].freeze
        # rubocop:enable Style/FormatStringToken

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :template, klass: self)

        ##
        # Ensures a non-empty template +string+ option and an +item_scope+ for sibling lookup.
        #
        # @param _value [String] current selector value (unused here)
        # @param context [Selectors::Context] must include options[:string] and item_scope
        # @return [void]
        # @raise [InvalidType] when the template string is blank
        # @raise [MissingOption] when item_scope is missing
        def self.validate_args!(_value, context)
          string = context.options&.dig(:string).to_s
          raise InvalidType, 'The `string` template is absent.' if string.empty?

          return if context.item_scope

          raise MissingOption, 'The post-processor context is missing `item_scope`.', [], cause: nil
        end

        ##
        # @param value [String]
        # @param context [Selectors::Context]
        def initialize(value, context)
          super

          @options = context.options || {}
          @string = @options[:string].to_s
          @getter = ->(key) { item_value(key) }
        end

        ##
        # @return [String]
        def get
          Html2rss::Config::DynamicParams.call(@string, {}, getter: @getter, replace_missing_with: '')
        end

        private

        # @param key [String, Symbol]
        # @return [String]
        def item_value(key)
          key = key.to_sym
          return value if key == :self

          @context.item_scope.select(key)
        end
      end
    end
  end
end
