# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Flattens configured category selector names into discrete category strings.
    # When a selector matches multiple nodes, each node is extracted independently
    # (with optional post-processors) so multi-tag UIs become multiple categories.
    #
    # Stateless: resolve config and nested selects through +scope.scraper+ / +scope.select+.
    module CategoriesExtractor
      module_function

      ##
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
      module_function :extract_category_values
      private_class_method :extract_category_values

      def extract_categories_from_node(node, scope:, config:)
        values = Extractors.get(config.merge(base_url: scope.base_url, selector: nil), node)
        values = apply_post_process(scope:, value: values, post_process_steps: config[:post_process])

        Array(values).filter_map { |category| extract_category_text(category) }
      end
      module_function :extract_categories_from_node
      private_class_method :extract_categories_from_node

      def apply_post_process(scope:, value:, post_process_steps:)
        return value unless value && post_process_steps

        steps = post_process_steps.is_a?(Array) ? post_process_steps : [post_process_steps]
        steps.each do |options|
          value = PostProcessors.get(options[:name], value, scope.context_for(options:))
        end
        value
      end
      module_function :apply_post_process
      private_class_method :apply_post_process

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
      module_function :extract_category_text
      private_class_method :extract_category_text

      def node_set_with_multiple_elements?(nodes)
        nodes.is_a?(Nokogiri::XML::NodeSet) && nodes.length > 1
      end
      module_function :node_set_with_multiple_elements?
      private_class_method :node_set_with_multiple_elements?

      def extract_nodes(item:, config:)
        return unless config.respond_to?(:[]) && config[:selector]

        Extractors.element(item, config[:selector])
      end
      module_function :extract_nodes
      private_class_method :extract_nodes
    end
  end
end
