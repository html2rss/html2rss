# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # One config-facing option on an extractor or post-processor strategy.
    #
    # Strategies own an +OPTIONS+ Array of these. This type is also the
    # introspection SoT (+for+ / +expectation_for+); {SchemaExport} maps Ruby
    # types to JSON Schema only.
    OptionSpec = Data.define(:name, :type, :required) do
      # Maps Ruby option types to JSON Schema +type+ strings.
      # rubocop:disable-next Lint/ConstantDefinitionInBlock -- Data.define type constant
      RUBY_TO_JSON_TYPE = {
        String => 'string',
        Integer => 'integer',
        Hash => 'object',
        Array => 'array'
      }.freeze

      # Human-readable labels for validation error messages.
      # rubocop:disable-next Lint/ConstantDefinitionInBlock -- Data.define type constant
      TYPE_LABELS = {
        Integer => 'an integer',
        String => 'a string',
        Hash => 'a hash'
      }.freeze

      # @param name [Symbol, String]
      # @param type [Class, Array<Class>]
      # @param required [Boolean]
      def initialize(name:, type:, required: true)
        super(name: name.to_sym, type:, required:)
      end

      ##
      # @param actual [Object]
      # @return [Boolean]
      def valid_type?(actual)
        self.class.valid_type?(actual, type)
      end

      ##
      # @param optional [Boolean]
      # @return [String]
      def error_message(optional: !required)
        suffix = optional ? ' or omitted' : ''
        "`#{name}` must be #{type_failure_label}#{suffix}"
      end

      ##
      # @return [String, Array<String>]
      def json_type
        self.class.json_type_for(type)
      end

      private

      def type_failure_label
        case type
        when Array then type.map { |t| TYPE_LABELS.fetch(t) { "a #{t}" } }.join(' or ')
        else TYPE_LABELS.fetch(type) { "a #{type}" }
        end
      end

      class << self
        ##
        # @param actual [Object]
        # @param type_or_types [Class, Array<Class>]
        # @return [Boolean]
        def valid_type?(actual, type_or_types)
          case type_or_types
          when Array then type_or_types.any? { |t| actual.is_a?(t) }
          else actual.is_a?(type_or_types)
          end
        end

        ##
        # @param ruby_type [Class, Array<Class>]
        # @return [String, Array<String>]
        def json_type_for(ruby_type)
          case ruby_type
          when Array then ruby_type.map { |t| json_type_for(t) }
          else
            RUBY_TO_JSON_TYPE.fetch(ruby_type) do
              raise ArgumentError, "unsupported OPTIONS type mapping for #{ruby_type}"
            end
          end
        end

        ##
        # @param klass [Class] extractor or post-processor class
        # @return [Array<OptionSpec>]
        def for(klass)
          klass.const_defined?(:OPTIONS) ? klass::OPTIONS : []
        end

        ##
        # Ruby-typed expectation for a leaf under a selector / post-process parent.
        #
        # @param parent [Hash] selector or post-process step hash
        # @param leaf [Symbol] option key under +parent+
        # @return [Hash{Symbol => Object}, nil] +{ type:, required: }+ with Ruby +type+
        def expectation_for(parent:, leaf:)
          option = option_for(parent, leaf)
          return unless option

          { type: option.type, required: option.required }
        end

        ##
        # Resolves an OptionSpec for a parent hash and option leaf name.
        #
        # @param parent [Hash] selector or post-process step hash
        # @param leaf [Symbol, String]
        # @return [OptionSpec, nil]
        def option_for(parent, leaf)
          leaf = leaf.to_sym
          if (name = parent[:extractor] || parent['extractor'])
            klass = Extractors::NAME_TO_CLASS[name.to_sym]
            return find_option(klass, leaf) if klass
          end

          if (name = parent[:name] || parent['name'])
            klass = PostProcessors::NAME_TO_CLASS[name.to_sym]
            return find_option(klass, leaf) if klass
          end

          nil
        end

        private

        def find_option(klass, leaf)
          self.for(klass).find { |spec| spec.name == leaf }
        end
      end
    end
  end
end
