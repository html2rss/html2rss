# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # JSON export adapter from the runtime validators to the packaged schema artifact.
    module Schema
      module_function

      # Canonical filename for the exported config JSON schema artifact.
      SCHEMA_FILENAME = 'html2rss-config.schema.json'

      ##
      # Returns the exported configuration JSON Schema.
      #
      # @return [Hash{String => Object}] JSON Schema represented as a Ruby hash
      def json_schema
        load_json_schema_extension!
        Builder.call
      end

      ##
      # Resolves the packaged schema path used by downstream tools.
      #
      # @return [String] absolute path to the packaged JSON schema file
      def path
        search_path = File.expand_path(__dir__)

        loop do
          candidate = File.join(search_path, 'schema', SCHEMA_FILENAME)
          return candidate if File.exist?(candidate)

          parent_path = File.dirname(search_path)
          break if parent_path == search_path

          search_path = parent_path
        end

        File.expand_path("../../../schema/#{SCHEMA_FILENAME}", __dir__)
      end

      # @return [void]
      def load_json_schema_extension!
        require 'dry/schema/extensions/json_schema'
        Dry::Schema.load_extensions(:json_schema)
      end

      ##
      # Orchestrates schema assembly from runtime validator contracts plus
      # client-facing overlays.
      class Builder
        class << self
          # @return [Hash{String => Object}] fully assembled JSON schema hash
          def call
            new.call
          end
        end

        # @return [Hash{String => Object}] fully assembled JSON schema hash
        def call
          schema = validator_schema
          apply_top_level(schema)
          schema.fetch(:properties).merge!(overlay)
          schema.fetch(:properties).delete(:dynamic_params_error)
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

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
        def overlay
          items_schema = Html2rss::Config::SelectorsValidator::Items.new.schema.json_schema(loose: true)
          items_schema[:properties][:pagination] = {
            description: 'Pagination configuration or maximum page count integer.',
            oneOf: [
              { type: 'integer', exclusiveMinimum: 0 },
              {
                type: 'object',
                properties: {
                  strategy: { type: 'string', enum: Html2rss::RequestSession::Pager.strategy_names },
                  max_pages: { type: 'integer', exclusiveMinimum: 0 },
                  selector: { type: 'string' },
                  param: { type: 'string' },
                  start_page: { type: 'integer' },
                  step: { type: 'integer', exclusiveMinimum: 0 },
                  start_offset: { type: 'integer' },
                  increment: { type: 'integer', exclusiveMinimum: 0 },
                  cursor_path: { type: 'string' },
                  next_url_path: { type: 'string' }
                },
                additionalProperties: true
              }
            ]
          }

          {
            strategy: {
              type: 'string',
              not: { type: 'null' }
            },
            headers: {
              type: 'object',
              description: 'HTTP headers applied to every request.',
              additionalProperties: { type: 'string' }
            },
            stylesheets: {
              type: 'array',
              description: 'Collection of stylesheets to attach to the RSS feed.',
              items: Html2rss::Config::Validator::StylesheetConfig.json_schema(loose: true)
            },
            auto_source: Html2rss::Config::AutoSourceContract.json_schema(loose: true).merge(
              default: DeepStringifier.call(Html2rss::AutoSource::DEFAULT_CONFIG)
            ),
            selectors: {
              type: 'object',
              description: 'Selectors used to extract article attributes.',
              properties: {
                items: items_schema.merge(
                  description: 'Defines the items selector and optional enhancement settings.'
                ),
                enclosure: Html2rss::Config::SelectorsValidator::Enclosure.new.schema.json_schema(loose: true).merge(
                  description: 'Describes enclosure extraction settings.'
                ),
                guid: reference_array('List of selector keys used to build the GUID. Each entry must reference a sibling selector key; runtime validation enforces those references.'),
                categories: reference_array('List of selector keys whose values will be used as categories. Each entry must reference a sibling selector key; runtime validation enforces those references.')
              },
              patternProperties: {
                '^(?!items$|enclosure$|guid$|categories$).+$' => Html2rss::Config::SelectorsValidator::Selector.new.schema.json_schema(loose: true).merge(
                  description: 'Dynamic selector definition keyed by attribute name.'
                )
              },
              additionalProperties: true
            }
          }
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength

        def reference_array(description)
          {
            type: 'array',
            description:,
            minItems: 1,
            items: {
              type: 'string',
              description: 'Selector key defined elsewhere in this object.'
            }
          }
        end
      end

      ##
      # Converts nested hash keys to strings so the resulting schema serializes cleanly.
      module DeepStringifier
        module_function

        # @param object [Hash, Array, Object] nested data to normalize
        # @return [Hash, Array, Object] deep copy with stringified hash keys
        def call(object)
          case object
          when Hash
            stringify_hash(object)
          when Array
            object.map { |value| call(value) }
          when Symbol
            object.to_s
          else
            object
          end
        end

        # @param object [Hash{Object => Object}] hash whose keys should become strings
        # @return [Hash{String => Object}] hash with recursively normalized values
        def stringify_hash(object)
          object.to_h { |key, value| [key.to_s, call(value)] }
        end
      end
    end
  end
end
