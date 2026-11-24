# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Per-field extraction plans compiled once from the static selector config, and the one
    # extract-then-post-process path that runs them against an item node.
    #
    # Owns extractor lookup, post-processor validation ({PostProcessors} options are checked here, once),
    # and the special fields (+enclosure+, +guid+, +categories+). Nested selects go back through the
    # {ItemEnv} scope so the caller's dispatch stays the single entry.
    class FieldPlan
      # Per-field extraction plan: extractor class and validated post-processor steps.
      CompiledField = Data.define(:name, :article_key, :config, :extractor_class, :post_process_steps, :special)
      private_constant :CompiledField

      # Config selector keys that map onto a different {Article} attribute.
      # +:enclosure+ stays singular in YAML; Article stores +:enclosures+.
      SELECTOR_TO_ARTICLE_KEY = { enclosure: :enclosures }.freeze
      # Item attributes that require dedicated extraction logic.
      SPECIAL_ATTRIBUTES = Set[:guid, :enclosure, :categories].freeze

      # @param selectors [Hash] the feed config's +selectors+
      # @param except [Symbol] selector key that is not a field (the items selector)
      def initialize(selectors, except:)
        @fields = selectors.each_with_object({}) do |(name, config), acc|
          acc[name] = compile_field(name, config) unless name == except
        end
      end

      ##
      # @param name [Symbol] selector key
      # @return [CompiledField, nil] the compiled field, or nil when the key is no field
      def [](name) = @fields[name]

      ##
      # Extracts a field's value (and post-processes it) for the item in +scope+.
      #
      # @param field [CompiledField]
      # @param scope [ItemEnv]
      # @return [Object, Array<Object>, nil]
      # @raise [InvalidSelectorName] when the field has no config
      def select(field, scope)
        raise InvalidSelectorName, "Selector for '#{field.name}' is not defined." if field.config.nil?

        field.special ? select_special(field, scope) : select_regular(field, scope)
      end

      private

      def compile_field(name, config)
        CompiledField.new(
          name:,
          article_key: SELECTOR_TO_ARTICLE_KEY.fetch(name, name),
          config:,
          extractor_class: extractor_class_for(config),
          post_process_steps: compile_post_process_steps(config),
          special: SPECIAL_ATTRIBUTES.member?(name)
        )
      end

      def extractor_class_for(config)
        return unless config.is_a?(Hash)

        Extractors::NAME_TO_CLASS[config[:extractor]&.to_sym || Extractors::DEFAULT_EXTRACTOR]
      end

      def compile_post_process_steps(config)
        return unless config.is_a?(Hash) && config[:post_process]

        steps = config[:post_process]
        (steps.is_a?(Array) ? steps : [steps]).map { |step| compile_post_process_step(step) }
      end

      def compile_post_process_step(step)
        klass = PostProcessors::NAME_TO_CLASS[step[:name].to_sym]
        raise PostProcessors::UnknownPostProcessorName, "Unknown name '#{step[:name]}'" unless klass

        klass.validate_options!(StepEnv.new(step_config: step))
        [klass, step]
      end

      def select_special(field, scope)
        case field.name
        when :enclosure
          enclosure(field, scope)
        when :guid
          Array(field.config).map { |selector_name| scope.select(selector_name) }
        when :categories
          select_categories(field.config, scope)
        end
      end

      def select_regular(field, scope)
        run_field(field, scope.item, scope, selector: field.config[:selector])
      end

      # The one extract-then-post-process path for every field, whatever node it runs on.
      def run_field(field, node, scope, selector:)
        value = field.extractor_class.new(
          node,
          selector:,
          attribute: field.config[:attribute],
          static: field.config[:static],
          base_url: scope.base_url
        ).call

        apply_post_process(scope, value, field.post_process_steps)
      end

      def apply_post_process(scope, value, steps)
        return value unless value && steps

        value = value.to_s if value.is_a?(Url) # post-processors work on text
        steps.each do |klass, step_config|
          value = klass.new(value, scope.context_for(step_config:)).call
        end

        value
      end

      # Flattens configured category selector names into discrete category strings.
      # When a selector matches multiple nodes, each node is extracted independently
      # (with optional post-processors) so multi-tag UIs become multiple categories.
      #
      # @param category_selectors [Array, String, Symbol]
      # @param scope [ItemEnv]
      # @return [Array<String>]
      def select_categories(category_selectors, scope)
        Array(category_selectors).flat_map do |selector_name|
          extract_category_values(selector_name, scope:)
        end
      end

      def extract_category_values(selector_name, scope:)
        field = self[selector_name.to_sym]
        return [] unless field&.config

        nodes = extract_nodes(item: scope.item, config: field.config)
        return Array(scope.select(selector_name)) unless nodes.is_a?(Nokogiri::XML::NodeSet) && nodes.length > 1

        nodes.flat_map { |node| extract_categories_from_node(node, scope:, field:) }
      end

      def extract_categories_from_node(node, scope:, field:)
        values = run_field(field, node, scope, selector: nil)

        Array(values).filter_map { |category| category.to_s.strip.then { _1 unless _1.empty? } }
      end

      def extract_nodes(item:, config:)
        return unless config.is_a?(Hash) && config[:selector]

        Extractors.element(item, config[:selector])
      end

      # @return [Hash, nil] enclosure details, or nil when the selector yields nothing or no http(s) URL
      #   ({Url.resolve_web})
      def enclosure(field, scope)
        selected = select_regular(field, scope)
        return unless (url = Url.resolve_web(selected, scope.base_url))

        { url:, type: field.config[:content_type] }
      end
    end
  end
end
