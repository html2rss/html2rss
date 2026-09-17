# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Builds JSON Schema fragments from extractor / post-processor class constants.
    #
    # Each registry class owns +DESCRIPTION+, +EXAMPLES+, and optional +OPTIONS+;
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
        options_for(klass).each do |spec|
          properties[spec.name] = property_schema_for(spec.type)
        end
        properties
      end

      ##
      # @param klass [Class]
      # @return [Array<String>]
      def post_processor_required(klass)
        required = ['name']
        required + options_for(klass).select(&:required).map { |spec| spec.name.to_s }
      end

      ##
      # @param klass [Class]
      # @return [Array<Option>]
      def options_for(klass)
        klass.const_defined?(:OPTIONS) ? klass::OPTIONS : []
      end

      ##
      # @param ruby_type [Class, Array<Class>]
      # @return [Hash{Symbol => String, Array<String>}]
      def property_schema_for(ruby_type)
        { type: json_type_for(ruby_type) }
      end

      ##
      # @param ruby_type [Class, Array<Class>]
      # @return [String, Array<String>]
      def json_type_for(ruby_type)
        case ruby_type
        when Array
          ruby_type.map { |type| json_type_for(type) }
        else
          RUBY_TO_JSON_TYPE.fetch(ruby_type) do
            raise ArgumentError, "unsupported OPTIONS type mapping for #{ruby_type}"
          end
        end
      end
    end
  end
end