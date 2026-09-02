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
      # rubocop:disable Metrics/ClassLength -- overlay assembly stays in one builder
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
          schema[:$defs] = registry_catalog_defs
          schema.fetch(:properties).merge!(overlay)
          schema.fetch(:properties).delete(:dynamic_params_error)
          HashUtil.deep_stringify_keys(schema)
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

          topics = schema.dig(:properties, :directory, :properties, :topics)
          topics[:minItems] = 1 if topics.is_a?(Hash)
          apply_botasaurus_schema!(schema)
        end

        def apply_botasaurus_schema!(schema)
          request = schema.dig(:properties, :request, :properties)
          return unless request.is_a?(Hash)

          exported = Html2rss::Config::Validator::BotasaurusRequestExport
                     .new.schema.json_schema(loose: true).except(:$schema)
          exported[:additionalProperties] = false
          exported.fetch(:properties).fetch(:window_size)[:additionalProperties] = false
          request[:botasaurus] = exported
        end

        # @return [Hash{Symbol => Hash}] catalog under $defs.post_processors / $defs.extractors
        def registry_catalog_defs
          {
            post_processors: catalog_from_registry(Selectors::PostProcessors::NAME_TO_CLASS),
            extractors: catalog_from_registry(Selectors::Extractors::NAME_TO_CLASS)
          }
        end

        # @param registry [Hash{Symbol => Class}]
        # @return [Hash{String => Hash}]
        def catalog_from_registry(registry)
          registry.keys.sort.to_h { |name| [name.to_s, registry.fetch(name).schema_doc] }
        end

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
        def overlay
          items_schema = Html2rss::Config::SelectorsValidator::Items.new.schema.json_schema(loose: true)
          items_schema[:properties][:enhance] = items_schema.fetch(:properties).fetch(:enhance).merge(
            description: 'List-card enrichment: run Html::ArticleExtractor on each matched item node ' \
                         'to fill missing fields from the card HTML.'
          )
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

          selector_schema = Schema.apply_selector_registry_refs!(
            Html2rss::Config::SelectorsValidator::Selector.new.schema.json_schema(loose: true)
          )
          enclosure_schema = Schema.apply_selector_registry_refs!(
            Html2rss::Config::SelectorsValidator::Enclosure.new.schema.json_schema(loose: true)
          )

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
              default: HashUtil.deep_stringify_keys(Html2rss::AutoSource::DEFAULT_CONFIG)
            ),
            selectors: {
              type: 'object',
              description: 'Selectors used to extract article attributes.',
              properties: {
                items: items_schema.merge(
                  description: 'Defines the items selector and list-card enhance settings.'
                ),
                enclosure: enclosure_schema.merge(
                  description: 'Describes enclosure extraction settings.'
                ),
                guid: reference_array('List of selector keys used to build the GUID. Each entry must reference a sibling selector key; runtime validation enforces those references.'),
                categories: reference_array('List of selector keys whose values will be used as categories. Each entry must reference a sibling selector key; runtime validation enforces those references.')
              },
              patternProperties: {
                '^(?!items$|enclosure$|guid$|categories$).+$' => selector_schema.merge(
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
      # rubocop:enable Metrics/ClassLength

      ##
      # Wires extractor / post_process to thin oneOf $refs into the registry catalog.
      #
      # @param schema [Hash] dry-schema JSON schema fragment for a selector
      # @return [Hash] same schema with registry $ref wiring applied
      def apply_selector_registry_refs!(schema)
        properties = schema.fetch(:properties)
        properties[:extractor] = extractor_wire_schema
        properties[:post_process] = post_process_wire_schema
        schema
      end

      # @return [Hash{Symbol => Object}]
      def extractor_wire_schema
        {
          description: 'Extractor used to pull a value from the selected element.',
          oneOf: registry_ref_list('extractors', Selectors::Extractors::NAME_TO_CLASS)
        }
      end

      # @return [Hash{Symbol => Object}]
      def post_process_wire_schema
        {
          type: 'array',
          description: 'Ordered transforms applied to the extracted value.',
          items: {
            oneOf: registry_ref_list('post_processors', Selectors::PostProcessors::NAME_TO_CLASS)
          }
        }
      end

      ##
      # @param catalog [String] $defs catalog name (`extractors` or `post_processors`)
      # @param registry [Hash{Symbol => Class}]
      # @return [Array<Hash>] oneOf entries of `{ '$ref' => ... }`
      def registry_ref_list(catalog, registry)
        registry.keys.sort.map do |name|
          { '$ref' => "#/$defs/#{catalog}/#{name}" }
        end
      end
    end
  end
end
