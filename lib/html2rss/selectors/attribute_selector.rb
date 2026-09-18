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
          select_categories(category_selectors: config, scope:)
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

      # Flattens configured category selector names into discrete category strings.
      # When a selector matches multiple nodes, each node is extracted independently
      # (with optional post-processors) so multi-tag UIs become multiple categories.
      #
      # @param category_selectors [Array, String, Symbol]
      # @param scope [ItemScope]
      # @return [Array<String>]
      def select_categories(category_selectors:, scope:)
        Array(category_selectors).flat_map do |selector_name|
          extract_category_values(selector_name, scope:)
        end
      end

      def extract_category_values(selector_name, scope:)
        _selector_key, config = scope.scraper.selector_config_for(selector_name, allow_nil: true)
        return [] unless config

        nodes = extract_nodes(item: scope.item, config:)
        return Array(scope.select(selector_name)) unless node_set_with_multiple_elements?(nodes)

        Array(nodes).flat_map { |node| extract_categories_from_node(node, scope:, config:) }
      end

      def extract_categories_from_node(node, scope:, config:)
        values = Extractors.get(config.merge(base_url: scope.base_url, selector: nil), node)
        values = apply_post_process_steps(scope:, value: values, post_process_steps: config[:post_process])

        Array(values).filter_map { |category| extract_category_text(category) }
      end

      def extract_category_text(category)
        text = case category
               when Nokogiri::XML::Node, Nokogiri::XML::NodeSet
                 Html2rss::Html::Navigator.extract_visible_text(category)
               else
                 category&.to_s
               end

        stripped = text&.strip
        stripped unless stripped.nil? || stripped.empty?
      end

      def node_set_with_multiple_elements?(nodes)
        nodes.is_a?(Nokogiri::XML::NodeSet) && nodes.length > 1
      end

      def extract_nodes(item:, config:)
        return unless config.respond_to?(:[]) && config[:selector]

        Extractors.element(item, config[:selector])
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
