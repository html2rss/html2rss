# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # One config-facing option on an extractor or post-processor strategy.
    #
    # Strategies own an +OPTIONS+ Array of these. This type is also the
    # introspection SoT (+for+ / +expectation_for+); {SchemaDoc} maps Ruby
    # types to JSON Schema only.
    Option = Data.define(:name, :type, :required) do
      # @param name [Symbol, String]
      # @param type [Class, Array<Class>]
      # @param required [Boolean]
      def initialize(name:, type:, required: true)
        super(name: name.to_sym, type:, required:)
      end

      class << self
        ##
        # @param klass [Class] extractor or post-processor class
        # @return [Array<Option>]
        def for(klass)
          klass.const_defined?(:OPTIONS) ? klass::OPTIONS : []
        end
        alias options_for for

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

        private

        def option_for(parent, leaf)
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

        def find_option(klass, leaf)
          self.for(klass).find { |spec| spec.name == leaf }
        end
      end
    end
  end
end
