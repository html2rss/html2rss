# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Builds a JSON schema representation of the configuration contract.
    #
    # This helper lives outside of the gem runtime so that generating schemas
    # remains a development-only concern. It relies on the dry-schema JSON
    # extension which is loaded lazily when the schema is requested.
    module Schema
      module_function

      ##
      # Build the JSON schema hash for the configuration contract.
      #
      # @return [Hash] JSON schema describing the Html2rss configuration.
      def json_schema
        load_json_schema_extension

        schema = validator_schema
        schema[:'$schema'] = 'https://json-schema.org/draft/2020-12/schema'
        schema[:anyOf] = [
          { 'required' => ['selectors'] },
          { 'required' => ['auto_source'] }
        ]

        properties = schema.fetch(:properties)
        properties[:headers] = headers_schema
        properties[:stylesheets] = stylesheets_schema
        properties[:auto_source] = auto_source_schema
        properties[:selectors] = selectors_schema

        deep_stringify_keys(schema)
      end

      def load_json_schema_extension
        return if @json_schema_extension_loaded

        require 'dry/schema/extensions/json_schema'
        Dry::Schema.load_extensions(:json_schema)

        @json_schema_extension_loaded = true
      end
      private_class_method :load_json_schema_extension

      def validator_schema
        Html2rss::Config::Validator.new.schema.json_schema(loose: true)
      end
      private_class_method :validator_schema

      def headers_schema
        {
          type: 'object',
          description: 'HTTP headers applied to every request.',
          additionalProperties: { type: 'string' }
        }
      end
      private_class_method :headers_schema

      def stylesheets_schema
        {
          type: 'array',
          description: 'Collection of stylesheets to attach to the RSS feed.',
          items: Html2rss::Config::Validator::StylesheetConfig.json_schema(loose: true)
        }
      end
      private_class_method :stylesheets_schema

      def auto_source_schema
        schema = Html2rss::AutoSource::Config.json_schema(loose: true)
        schema[:default] = deep_stringify_keys(Html2rss::AutoSource::DEFAULT_CONFIG)
        schema
      end
      private_class_method :auto_source_schema

      def selectors_schema
        {
          type: 'object',
          description: 'Selectors used to extract article attributes.',
          properties: selector_properties,
          patternProperties: selector_pattern_properties,
          additionalProperties: true
        }
      end
      private_class_method :selectors_schema

      def selector_properties
        {
          items: items_schema,
          enclosure: enclosure_schema,
          guid: selector_reference_array('List of selector keys used to build the GUID.'),
          categories: selector_reference_array('List of selector keys whose values will be used as categories.')
        }
      end
      private_class_method :selector_properties

      def selector_pattern_properties
        {
          RESERVED_SELECTOR_PATTERN => dynamic_selector_schema
        }
      end
      private_class_method :selector_pattern_properties

      RESERVED_SELECTOR_PATTERN = '^(?!items$|enclosure$|guid$|categories$).+$'

      def dynamic_selector_schema
        Html2rss::Selectors::Config::Selector.new.schema.json_schema(loose: true).merge(
          description: 'Dynamic selector definition keyed by attribute name.'
        )
      end
      private_class_method :dynamic_selector_schema

      def items_schema
        Html2rss::Selectors::Config::Items.new.schema.json_schema(loose: true).merge(
          description: 'Defines the items selector and optional enhancement settings.'
        )
      end
      private_class_method :items_schema

      def enclosure_schema
        Html2rss::Selectors::Config::Enclosure.new.schema.json_schema(loose: true).merge(
          description: 'Describes enclosure extraction settings.'
        )
      end
      private_class_method :enclosure_schema

      def selector_reference_array(description)
        {
          type: 'array',
          description: description,
          items: {
            type: 'string',
            description: 'Selector key defined elsewhere in this object.'
          }
        }
      end
      private_class_method :selector_reference_array

      def deep_stringify_keys(object)
        case object
        when Hash
          object.each_with_object({}) do |(key, value), result|
            result[key.to_s] = deep_stringify_keys(value)
          end
        when Array
          object.map { |value| deep_stringify_keys(value) }
        else
          object
        end
      end
      private_class_method :deep_stringify_keys
    end
  end
end
