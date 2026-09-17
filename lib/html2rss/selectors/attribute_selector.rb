# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Dispatches selector extraction for regular and special attributes
    # (+enclosure+, +guid+, +categories+). Single public entry: {#call}.
    class AttributeSelector
      ##
      # @param selector_key [Symbol]
      # @param scope [ItemScope]
      # @param config [Hash, Array, nil]
      # @return [Object, Array<Object>, nil]
      def call(selector_key, scope:, config:)
        return default_item_url(scope.item, scope.base_url) if fallback_url_selector?(selector_key, config, scope.item)
        raise InvalidSelectorName, "Selector for '#{selector_key}' is not defined." if config.nil?

        if SPECIAL_ATTRIBUTES.member?(selector_key)
          select_special(selector_key, scope:, config:)
        else
          select_regular(selector_key, scope:, config:)
        end
      end

      private

      def select_special(name, scope:, config:)
        case name
        when :enclosure
          enclosure(scope:, config:)
        when :guid
          Array(config).map { |selector_name| scope.select(selector_name) }
        when :categories
          CategoriesExtractor.select_categories(category_selectors: config, scope:)
        end
      end

      def select_regular(_name, scope:, config:)
        merged_config = config.merge(base_url: scope.base_url)
        value = Extractors.get(merged_config, scope.item)

        apply_post_process_steps(scope:, value:, post_process_steps: config[:post_process])
      end

      def apply_post_process_steps(scope:, value:, post_process_steps:)
        return value unless value && post_process_steps

        steps = post_process_steps.is_a?(Array) ? post_process_steps : [post_process_steps]
        post_process(scope, value, steps)
      end

      def post_process(scope, value, post_process_steps)
        post_process_steps.each do |options|
          value = PostProcessors.get(options[:name], value, scope.context_for(options:))
        end

        value
      end

      # @return [Hash, nil] enclosure details, or nil when the selector yields nothing.
      def enclosure(scope:, config:)
        selected = select_regular(:enclosure, scope:, config:)
        return if selected.nil? || selected.to_s.strip.empty?

        url = Url.from_relative(selected, scope.base_url)

        { url:, type: config[:content_type] }
      end

      def fallback_url_selector?(selector_key, config, item)
        selector_key == :url && config.nil? && anchor_element?(item)
      end

      def anchor_element?(item)
        item.respond_to?(:name) && item.name.to_s.casecmp('a').zero?
      end

      def default_item_url(item, base_url)
        href = item['href'].to_s.strip
        return if href.empty?

        Url.from_relative(href, base_url)
      end
    end
  end
end
