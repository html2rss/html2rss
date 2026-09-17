# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Resolves config-facing {Option} expectations from an extractor or
    # post-processor parent hash. Single owner for option lookup used by
    # validation adapters (e.g. +Config::IssueMapper+).
    module OptionContract
      module_function

      ##
      # @param parent [Hash] selector or post-process step hash
      # @param leaf [Symbol] option key under +parent+
      # @return [Hash{Symbol => Object}, nil] +{ type:, required: }+ JSON-oriented expectation
      def expectation_for(parent:, leaf:)
        option = option_for(parent, leaf)
        return unless option

        { type: SchemaDoc.json_type_for(option.type), required: option.required }
      end

      ##
      # @param parent [Hash]
      # @param leaf [Symbol]
      # @return [Option, nil]
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
      private_class_method :option_for

      def find_option(klass, leaf)
        SchemaDoc.options_for(klass).find { |spec| spec.name == leaf }
      end
      private_class_method :find_option
    end
  end
end
