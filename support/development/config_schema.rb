# frozen_string_literal: true

require 'dry/schema/extensions/json_schema'

Dry::Schema.load_extensions(:json_schema)

module Html2rss
  class Config
    ##
    # Provides development helpers for generating the configuration JSON schema.
    module Schema
      module_function

      def json_schema
        Builder.call
      end
    end
  end
end

module Html2rss
  class Config
    module Schema
      ##
      # Orchestrates the assembly of the JSON schema using the runtime validator
      # contracts.
      class Builder
        class << self
          def call
            new.call
          end
        end

        def call
          schema = validator_schema
          apply_top_level(schema)
          assign_properties(schema.fetch(:properties))
          DeepStringifier.call(schema)
        end

        private

        def validator_schema
          Html2rss::Config::Validator.new.schema.json_schema(loose: true)
        end

        def apply_top_level(schema)
          schema['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
          schema[:anyOf] = [
            { 'required' => ['selectors'] },
            { 'required' => ['auto_source'] }
          ]
        end

        def assign_properties(properties)
          properties[:headers] = Components.headers
          properties[:stylesheets] = Components.stylesheets
          properties[:auto_source] = Components.auto_source
          properties[:selectors] = Components.selectors
        end
      end
    end
  end
end

module Html2rss
  class Config
    module Schema
      ##
      # Exposes schema fragments that populate the top-level configuration schema.
      module Components
        module_function

        def headers
          {
            type: 'object',
            description: 'HTTP headers applied to every request.',
            additionalProperties: { type: 'string' }
          }
        end

        def stylesheets
          {
            type: 'array',
            description: 'Collection of stylesheets to attach to the RSS feed.',
            items: Html2rss::Config::Validator::StylesheetConfig.json_schema(loose: true)
          }
        end

        def auto_source
          schema = Html2rss::AutoSource::Config.json_schema(loose: true)
          schema[:default] = DeepStringifier.call(Html2rss::AutoSource::DEFAULT_CONFIG)
          schema
        end

        def selectors
          Selectors.schema
        end
      end
    end
  end
end

module Html2rss
  class Config
    module Schema
      ##
      # Provides schema fragments that document selector configuration.
      module Selectors
        module_function

        RESERVED_SELECTOR_PATTERN = '^(?!items$|enclosure$|guid$|categories$).+$'

        def schema
          {
            type: 'object',
            description: 'Selectors used to extract article attributes.',
            properties: selector_properties,
            patternProperties: pattern_properties,
            additionalProperties: true
          }
        end

        def selector_properties
          {
            items: items_schema,
            enclosure: enclosure_schema,
            guid: reference_array('List of selector keys used to build the GUID.'),
            categories: reference_array('List of selector keys whose values will be used as categories.')
          }
        end

        def pattern_properties
          { RESERVED_SELECTOR_PATTERN => dynamic_selector_schema }
        end

        def dynamic_selector_schema
          Html2rss::Selectors::Config::Selector.new.schema.json_schema(loose: true).merge(
            description: 'Dynamic selector definition keyed by attribute name.'
          )
        end

        def items_schema
          Html2rss::Selectors::Config::Items.new.schema.json_schema(loose: true).merge(
            description: 'Defines the items selector and optional enhancement settings.'
          )
        end

        def enclosure_schema
          Html2rss::Selectors::Config::Enclosure.new.schema.json_schema(loose: true).merge(
            description: 'Describes enclosure extraction settings.'
          )
        end

        def reference_array(description)
          {
            type: 'array',
            description:,
            items: {
              type: 'string',
              description: 'Selector key defined elsewhere in this object.'
            }
          }
        end
      end
    end
  end
end

module Html2rss
  class Config
    module Schema
      ##
      # Converts nested hash keys to strings so the resulting schema serializes cleanly.
      module DeepStringifier
        module_function

        def call(object)
          case object
          when Hash
            stringify_hash(object)
          when Array
            object.map { |value| call(value) }
          else
            object
          end
        end

        def stringify_hash(object)
          object.each_with_object({}) do |(key, value), result|
            result[key.to_s] = call(value)
          end
        end
      end
    end
  end
end
