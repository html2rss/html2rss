# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Holds the configurations of the selectors.
    class Selectors
      def initialize(feed_config)
        @feed_config = feed_config
      end

      ##
      # @param name [Symbol]
      # @return [true, false]
      def attribute?(name)
        attribute_names.include?(name)
      end

      def attribute(name)
        raise "invalid attribute: #{name}" unless attribute?(name)

        feed_config.dig(:selectors, name)
      end

      ##
      # @return [Array<Symbol>]
      def category_selectors
        selector_names_for(:categories)
      end

      ##
      # @return [Array<Symbol>]
      def guid_selectors
        selector_names_for(:guid, default: :title_or_description)
      end

      ##
      # @param name [Symbol]
      # @return [String]
      def selector(name)
        feed_config.dig(:selectors, name, :selector)
      end

      ##
      # @return [Array<String>]
      def attribute_names
        @attribute_names ||= feed_config.fetch(:selectors, {}).keys.tap { |attrs| attrs.delete(:items) }
      end

      ##
      # @return [Symbol]
      def items_order
        feed_config.dig(:selectors, :items, :order)&.to_sym
      end

      private

      attr_reader :feed_config

      ##
      # Returns the selector names for selector `name`. If none, returns [default].
      # @param name [Symbol]
      # @param default [String, Symbol]
      # @return [Array<Symbol>]
      def selector_names_for(name, default: nil)
        feed_config[:selectors].fetch(name) { Array(default) }.tap do |array|
          array.reject! { |entry| entry.to_s == '' }
          array.map!(&:to_sym)
          array.uniq!
        end
      end
    end
  end
end
