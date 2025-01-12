# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
    ##
    # Returns a formatted String according to the string pattern.
    #
    # If +self+ is used, the selectors extracted value will be used.
    # It uses [Kernel#format](https://ruby-doc.org/core/Kernel.html#method-i-format)
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
    #          string: '%{self} (%{price})'
    #
    # Would return:
    #    'Product (23,42€)'
    class Template < Base
      def self.validate_args!(value, context)
        assert_type value, String, :value, context:

        string = context[:options]&.dig(:string).to_s
        raise InvalidType, 'The `string` template is absent.' if string.empty?
      end

      ##
      # @param value [String]
      # @param context [Item::Context]
      def initialize(value, context)
        super

        @options = context[:options] || {}
        @scraper = context[:scraper]
        @item = context[:item]
        @string = @options[:string].to_s
      end

      ##
      # @return [String]
      def get
        @options[:methods] ? format_string_with_methods : format_string_with_dynamic_params
      end

      private

      ##
      # @return [String] the string containing the template
      attr_reader :string

      ##
      # @return [Array<String>]
      def methods
        @methods ||= @options[:methods].map { |method_name| item_value(method_name) }
      end

      ##
      # Formats a string using methods.
      #
      # @return [String]
      # @deprecated Use %<id>s formatting instead. Will be removed in version 1.0.0. See README / Dynamic parameters.
      def format_string_with_methods
        Log.warn '[DEPRECATION] This method of using params is deprecated and \
                  support for it will be removed in version 1.0.0.\
                  Please use dynamic parameters (i.e. %<id>s, see README.md) instead.'

        string % methods
      end

      ##
      # @return [String]
      def format_string_with_dynamic_params
        SelectorsScraper::DynamicParams.call(string, {}, getter: method(:item_value))
      end

      ##
      # @param method_name [String, Symbol]
      # @return [String]
      def item_value(key)
        key = key.to_sym
        key == :self ? value : @scraper.select(key, @item)
      end
    end
  end
end
