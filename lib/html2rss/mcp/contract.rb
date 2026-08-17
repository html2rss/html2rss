# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Published MCP contract: strategy enum, input/output schemas, listing
    # annotations, and the single compact JSON envelope response.
    module Contract # rubocop:disable Metrics/ModuleLength -- published listing constants stay co-located
      STRATEGIES = %w[auto faraday botasaurus].freeze

      URL_PROPERTY = {
        type: 'string',
        format: 'uri',
        description: 'Source page URL'
      }.freeze

      STRATEGY_PROPERTY = {
        type: 'string',
        enum: STRATEGIES,
        default: 'auto',
        description: 'Request strategy (auto runs faraday → botasaurus fallback chain)'
      }.freeze

      INSPECT_STRATEGY_PROPERTY = STRATEGY_PROPERTY.merge(
        description: 'Request strategy (auto uses Faraday for cheap diagnostics; pin botasaurus when needed)'
      ).freeze

      XOR_ONE_OF = [
        { required: %w[config], not: { required: %w[yaml] } }.freeze,
        { required: %w[yaml], not: { required: %w[config] } }.freeze
      ].freeze

      CONFIG_XOR_PROPERTIES = {
        config: {
          type: 'object',
          description: 'Feed configuration hash with channel and selectors (XOR yaml)'
        }.freeze,
        yaml: {
          type: 'string',
          pattern: '\\S',
          description: 'Feed configuration YAML string (XOR config)'
        }.freeze
      }.freeze

      CONFIG_XOR_SCHEMA = {
        type: 'object',
        properties: CONFIG_XOR_PROPERTIES,
        oneOf: XOR_ONE_OF
      }.freeze

      APPLY_INPUT_SCHEMA = {
        type: 'object',
        properties: { url: URL_PROPERTY, **CONFIG_XOR_PROPERTIES }.freeze,
        required: %w[url],
        oneOf: XOR_ONE_OF
      }.freeze

      SCRAPE_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          url: URL_PROPERTY,
          strategy: STRATEGY_PROPERTY,
          limit: { type: 'integer', description: 'Max articles to keep (default 25)', default: 25 },
          items_selector: { type: 'string', description: 'Optional CSS selector hint for items' }
        }.freeze,
        required: %w[url]
      }.freeze

      INSPECT_INPUT_SCHEMA = {
        type: 'object',
        properties: { url: URL_PROPERTY, strategy: INSPECT_STRATEGY_PROPERTY }.freeze,
        required: %w[url]
      }.freeze

      CAPTURE_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          url: URL_PROPERTY,
          strategy: STRATEGY_PROPERTY,
          items_selector: { type: 'string', description: 'Optional CSS selector hint for items' }
        }.freeze,
        required: %w[url]
      }.freeze

      ANNOTATIONS_OPEN_WORLD = {
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: true
      }.freeze

      ANNOTATIONS_VALIDATE = ANNOTATIONS_OPEN_WORLD.merge(open_world_hint: false).freeze

      TITLES = {
        scrape_url: 'Scrape URL',
        inspect_url: 'Inspect URL',
        capture_config: 'Capture feed config',
        validate_config: 'Validate feed config',
        apply_config: 'Apply feed config'
      }.freeze

      class << self
        ##
        # Envelope JSON Schema. Built lazily so Zeitwerk can load Contract before Outcome.
        #
        # @return [Hash]
        def output_schema # rubocop:disable Metrics/MethodLength -- schema document is one hash
          {
            type: 'object',
            additionalProperties: false,
            required: %w[ok next_step guidance payload],
            properties: {
              ok: { type: 'boolean' },
              next_step: { type: 'string', enum: Outcome::NextStep::NAMES.map(&:to_s) },
              guidance: { type: 'string' },
              payload: { type: 'object' }
            }
          }
        end

        ##
        # One envelope Hash, one compact JSON body, no +_meta+.
        #
        # @param outcome [Outcome]
        # @return [::MCP::Tool::Response]
        def response(outcome)
          wire = outcome.to_h
          ::MCP::Tool::Response.new(
            [{ type: 'text', text: JSON.generate(wire) }],
            error: !outcome.ok,
            structured_content: wire
          )
        end
      end
    end
  end
end
