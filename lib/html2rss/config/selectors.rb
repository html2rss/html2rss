# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Holds the configurations of the selectors.
    class Selectors
      ITEMS_SELECTOR_NAME = :items

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
      # @return [Hash<Symbol, Object>]
      def selector_attributes(name)
        raise "invalid attribute: #{name}" unless attribute?(name)

        config[name]
      end

      ##
      # @return [Array<Symbol>]
      def category_selectors
        selector_keys_for(:categories)
      end

      ##
      # @return [Array<Symbol>]
      def guid_selectors
        selector_keys_for(:guid, default: :title_or_description)
      end

      ##
      # @param name [Symbol]
      # @return [String]
      def selector(name)
        config.dig(name, :selector)
      end

      ##
      # @return [Array<String>]
      def attribute_names
        @attribute_names ||= config.keys.tap { |attrs| attrs.delete(ITEMS_SELECTOR_NAME) }
      end

      ##
      # @return [Symbol]
      def items_order
        config.dig(ITEMS_SELECTOR_NAME, :order)&.to_sym
      end

      private

      attr_reader :config

      ##
      # Returns the selector names for selector `name`. If none, returns [default].
      # @param name [Symbol]
      # @param default [String, Symbol]
      # @return [Array<Symbol,nil>]
      def selector_keys_for(name, default: nil)
        config.fetch(name) { Array(default) }.tap do |array|
          array.reject! { |entry| entry.to_s == '' }
          array.map!(&:to_sym)
          array.uniq!
        end
      end
    end
  end
end
