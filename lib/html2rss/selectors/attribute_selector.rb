# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Dispatches selector extraction for regular and special attributes
    # (+enclosure+, +guid+, +categories+). Owns extractor config-merge cache and
    # post-process application for selector values.
    class AttributeSelector
      ##
      # @param categories_extractor [CategoriesExtractor, nil] wired after construction
      def initialize(categories_extractor: nil)
        @categories_extractor = categories_extractor
        @merged_configs = {}
      end

      # Categories collaborator used for +:categories+ special selection.
      attr_writer :categories_extractor

      ##
      # @param selector_key [Symbol]
      # @param scope [ItemScope]
      # @param config [Hash, Array]
      # @return [Object, Array<Object>, nil]
      def dispatch_select(selector_key, scope:, config:)
        if SPECIAL_ATTRIBUTES.member?(selector_key)
          select_special(selector_key, scope:, config:)
        else
          select_regular(selector_key, scope:, config:)
        end
      end

      ##
      # @param name [Symbol]
      # @param scope [ItemScope]
      # @param config [Hash, Array]
      # @return [Object, Array<Object>, nil]
      def select_special(name, scope:, config:)
        case name
        when :enclosure
          enclosure(scope:, config:)
        when :guid
          Array(config).map { |selector_name| scope.select(selector_name) }
        when :categories
          @categories_extractor.select_categories(category_selectors: config, scope:)
        end
      end

      ##
      # @param _name [Symbol] unused; kept for call-site symmetry with +select_special+
      # @param scope [ItemScope]
      # @param config [Hash]
      # @return [Object, nil]
      def select_regular(_name, scope:, config:)
        merged_config = @merged_configs[[config.object_id, scope.base_url]] ||=
          config.merge(base_url: scope.base_url).freeze
        value = Extractors.get(merged_config, scope.item)

        apply_post_process_steps(scope:, value:, post_process_steps: config[:post_process])
      end

      ##
      # @param scope [ItemScope]
      # @param value [Object, nil]
      # @param post_process_steps [Array, Hash, nil]
      # @return [Object, nil]
      def apply_post_process_steps(scope:, value:, post_process_steps:)
        return value unless value && post_process_steps

        steps = post_process_steps.is_a?(Array) ? post_process_steps : [post_process_steps]
        post_process(scope, value, steps)
      end

      # Keep a single enclosure Hash as one list entry; +Array(hash)+ would split pairs.
      #
      # @param value [Hash, Array] enclosure hash or list of hashes
      # @return [Array]
      def wrap_enclosure_value(value)
        value.is_a?(Array) ? value : [value]
      end

      ##
      # @param item [Nokogiri::XML::Node]
      # @return [Boolean]
      def anchor_element?(item)
        item.respond_to?(:name) && item.name.to_s.casecmp('a').zero?
      end

      ##
      # @param selector_key [Symbol]
      # @param config [Hash, nil]
      # @param item [Nokogiri::XML::Node]
      # @return [Boolean]
      def fallback_url_selector?(selector_key, config, item)
        selector_key == :url && config.nil? && anchor_element?(item)
      end

      ##
      # @param item [Nokogiri::XML::Node]
      # @param base_url [String, Html2rss::Url]
      # @return [Html2rss::Url, nil]
      def default_item_url(item, base_url)
        href = item['href'].to_s.strip
        return if href.empty?

        Url.from_relative(href, base_url)
      end

      private

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
    end
  end
end
