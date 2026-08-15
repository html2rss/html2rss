# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Builds JSON Schema fragments from extractor / post-processor class constants.
    #
    # Each registry class owns +DESCRIPTION+, +EXAMPLES+, and optional +OPTION_TYPES+;
    # this module is the export adapter only.
    module SchemaDoc
      # Maps Ruby option types to JSON Schema +type+ strings.
      RUBY_TO_JSON_TYPE = {
        String => 'string',
        Integer => 'integer',
        Hash => 'object',
        Array => 'array'
      }.freeze

      module_function

      ##
      # @param name [Symbol, String] registry key
      # @param klass [Class] post-processor class
      # @return [Hash{Symbol => Object}] JSON Schema object for one post-processor
      def for_post_processor(name:, klass:)
        name = name.to_s
        {
          type: 'object',
          title: name,
          description: klass::DESCRIPTION,
          examples: klass::EXAMPLES,
          properties: post_processor_properties(name, klass),
          required: post_processor_required(klass),
          additionalProperties: true
        }
      end

      ##
      # @param name [Symbol, String] registry key
      # @param klass [Class] extractor class
      # @return [Hash{Symbol => Object}] JSON Schema for one extractor name
      def for_extractor(name:, klass:)
        name = name.to_s
        {
          type: 'string',
          const: name,
          title: name,
          description: klass::DESCRIPTION,
          examples: klass::EXAMPLES
        }
      end

      ##
      # @param name [String] registry key
      # @param klass [Class]
      # @return [Hash{Symbol => Hash}]
      def post_processor_properties(name, klass)
        properties = { name: { type: 'string', const: name } }
        option_types_for(klass).each do |field, ruby_type|
          properties[field] = { type: json_type_for(ruby_type) }
        end
        properties
      end
      module_function :post_processor_properties

      ##
      # @param klass [Class]
      # @return [Array<String>]
      def post_processor_required(klass)
        required = ['name']
        return required unless klass.const_defined?(:OPTION_TYPES)

        required + klass::OPTION_TYPES.keys.map(&:to_s)
      end
      module_function :post_processor_required

      ##
      # @param klass [Class]
      # @return [Hash{Symbol => Class}]
      def option_types_for(klass)
        types = {}
        types.merge!(klass::OPTION_TYPES) if klass.const_defined?(:OPTION_TYPES)
        types.merge!(klass::OPTIONAL_OPTION_TYPES) if klass.const_defined?(:OPTIONAL_OPTION_TYPES)
        types
      end
      module_function :option_types_for

      ##
      # @param ruby_type [Class]
      # @return [String]
      def json_type_for(ruby_type)
        RUBY_TO_JSON_TYPE.fetch(ruby_type) do
          raise ArgumentError, "unsupported OPTION_TYPES mapping for #{ruby_type}"
        end
      end
      module_function :json_type_for
    end
  end
end
