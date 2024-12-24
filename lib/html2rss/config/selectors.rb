# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Holds the configurations of the selectors.
    class Selectors
      ITEMS_SELECTOR_NAME = :items

      # Struct to represent a selector with associated attributes for extraction and processing.
      Selector = Struct.new(:selector, :attribute, :extractor, :post_process, :order, :static, :content_type,
                            keyword_init: true)

      # raised when an invalid selector name is used
      class InvalidSelectorName < Html2rss::Error; end

      ##
      # @param config [Hash<Symbol, Object>]
      def initialize(config)
        validate_config(config)
        @config = config
      end

      ##
      # @param name [Symbol]
      # @return [true, false]
      def selector?(name)
        name != ITEMS_SELECTOR_NAME && item_selector_names.include?(name)
      end

      ##
      # @param name [Symbol]
      # @return [Selector]
      def selector(name)
        raise InvalidSelectorName, "invalid selector name: #{name}" unless selector?(name)

        keywords = config[name].slice(*available_keys)

        if (additional_keys = keywords.keys - available_keys).any?
          Log.warn "additional keys (#{additional_keys.join(', ')}) present in selector #{name}"
        end

        Selector.new(keywords)
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
      # @return [Set<Symbol>]
      def item_selector_names
        @item_selector_names ||= config.keys.reject { |key| key == ITEMS_SELECTOR_NAME }.to_set
      end

      ##
      # @return [Symbol, nil]
      def items_order
        config.dig(ITEMS_SELECTOR_NAME, :order)&.to_sym
      end

      private

      attr_reader :config

      def validate_config(config)
        raise ArgumentError, 'selector for items is required' unless config[ITEMS_SELECTOR_NAME].is_a?(Hash)
      end

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

      def available_keys = @available_keys ||= Selector.members
    end
  end
end
