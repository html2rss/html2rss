# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Holds the configurations of the selectors.
    class Selectors
      ITEMS_SELECTOR_NAME = :items

      # Class to keep user-defined selectors.
      Selector = Struct.new('Selector',
                            :selector,
                            :attribute,
                            :extractor,
                            :post_process,
                            :order,
                            :static,
                            keyword_init: true)

      ##
      # @param config [Hash<Symbol, Object>]
      def initialize(config)
        raise ArgumentError, 'selector for items is required' unless config[ITEMS_SELECTOR_NAME].is_a?(Hash)

        @config = config
      end

      ##
      # @param name [Symbol]
      # @return [true, false]
      def selector?(name)
        raise "selector #{ITEMS_SELECTOR_NAME} must not be used as an item's selector" if name == ITEMS_SELECTOR_NAME

        item_selector_names.include?(name)
      end

      ##
      # @param name [Symbol]
      # @return [Selector]
      def selector(name)
        raise "invalid item's selector name: #{name}" unless selector?(name)

        Selector.new config[name]
      end

      ##
      # @return [Set<Symbol>]
      def category_selector_names
        selector_keys_for(:categories)
      end

      ##
      # @return [Set<Symbol>]
      def guid_selector_names
        selector_keys_for(:guid, default: :title_or_description)
      end

      ##
      # Returns the CSS/XPath selector.
      #
      # @param name [Symbol]
      # @return [String]
      def selector_string(name)
        Selector.new(config[name]).selector
      end

      ##
      # @return [Set<String>]
      def item_selector_names
        @item_selector_names ||= config.keys.tap { |attrs| attrs.delete(ITEMS_SELECTOR_NAME) }.to_set
      end

      ##
      # @return [Symbol, nil]
      def items_order
        config.dig(ITEMS_SELECTOR_NAME, :order)&.to_sym
      end

      private

      # @return [Hash<Symbol, Object>]
      attr_reader :config

      ##
      # Returns the selector keys for the selector named `name`. If none, returns [default].
      #
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
