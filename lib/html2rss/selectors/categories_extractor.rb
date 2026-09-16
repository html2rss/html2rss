# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Flattens configured category selector names into discrete category strings.
    # When a selector matches multiple nodes, each node is extracted independently
    # (with optional post-processors) so multi-tag UIs become multiple categories.
    class CategoriesExtractor
      ##
      # @param config_lookup [Method, #call] resolves selector name → +[key, config]+
      # @param attribute_selector [AttributeSelector] regular extract + post_process
      def initialize(config_lookup:, attribute_selector:)
        @config_lookup = config_lookup
        @attribute_selector = attribute_selector
        @category_node_configs = {}
      end

      ##
      # @param category_selectors [Array, String, Symbol]
      # @param scope [ItemScope]
      # @return [Array<String>]
      def select_categories(category_selectors:, scope:)
        Array(category_selectors).flat_map do |selector_name|
          extract_category_values(selector_name, scope:)
        end
      end

      private

      def extract_category_values(selector_name, scope:)
        selector_key, config = @config_lookup.call(selector_name, allow_nil: true)
        return [] unless config

        nodes = extract_nodes(item: scope.item, config:)
        unless node_set_with_multiple_elements?(nodes)
          return Array(@attribute_selector.select_regular(selector_key, scope:, config:))
        end

        Array(nodes).flat_map { |node| extract_categories_from_node(node, scope:, config:) }
      end

      def extract_categories_from_node(node, scope:, config:)
        values = Extractors.get(category_node_options(config, scope:), node)
        values = @attribute_selector.apply_post_process_steps(
          scope:,
          value: values,
          post_process_steps: config[:post_process]
        )

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

      def category_node_options(selector_config, scope:)
        @category_node_configs[[selector_config.object_id, scope.base_url]] ||= selector_config.merge(
          base_url: scope.base_url,
          selector: nil
        ).freeze
      end

      def extract_nodes(item:, config:)
        return unless config.respond_to?(:[]) && config[:selector]

        Extractors.element(item, config[:selector])
      end
    end
  end
end
