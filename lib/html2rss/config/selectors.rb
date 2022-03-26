# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Holds the configurations of the selectors.
    class Selectors
      ITEMS_SELECTOR_NAME = :items

      Selector = Struct.new('Selector', :selector, :order, :extractor, :attribute, :post_process, keyword_init: true)

      def initialize(config)
        raise ArgumentError, 'selector for items is required' unless config[ITEMS_SELECTOR_NAME].is_a?(Hash)

        @config = config
      end

      ##
      # @param name [Symbol]
      # @return [true, false]
      def attribute?(name)
        attribute_names.include?(name)
      end

      ##
      # @param name [Symbol]
      # @return [Selector]
      def selector(name)
        raise "invalid attribute: #{name}" unless attribute?(name)

        Selector.new config[name]
      end
      alias selector_attributes selector

      ##
      # @return [Set<Symbol>]
      def category_selectors
        selector_keys_for(:categories)
      end

      ##
      # @return [Set<Symbol>]
      def guid_selectors
        selector_keys_for(:guid, default: :title_or_description)
      end

      ##
      # Returns the CSS/XPath selector.
      # @param name [Symbol]
      # @return [String]
      def selector_string(name)
        Selector.new(config[name]).selector
      end

      ##
      # @return [Set<String>]
      def attribute_names
        @attribute_names ||= config.keys.tap { |attrs| attrs.delete(ITEMS_SELECTOR_NAME) }.to_set
      end

      ##
      # @return [Symbol, nil]
      def items_order
        config.dig(ITEMS_SELECTOR_NAME, :order)&.to_sym
      end

      private

      attr_reader :config

      ##
      # Returns the selector names for selector `name`. If none, returns [default].
      # @param name [Symbol]
      # @param default [String, Symbol]
      # @return [Set<Symbol>]
      def selector_keys_for(name, default: nil)
        config.fetch(name) { Array(default) }.tap do |array|
          array.reject! { |entry| entry.to_s == '' }
          array.map!(&:to_sym)
        end.to_set
      end
    end
  end
end
