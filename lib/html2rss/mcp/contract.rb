# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Published MCP contract: strategy enum, input/output schemas, listing
    # annotations, and the single compact JSON envelope response.
    module Contract # rubocop:disable Metrics/ModuleLength -- published listing constants stay co-located
      # Published MCP request strategies (excludes +local_file+).
      STRATEGIES = %w[auto faraday botasaurus].freeze

      # Raised when apply/validate config uses an unpublished MCP request adapter.
      class UnpublishedRequestError < ArgumentError; end

      # JSON Schema property for a source page URL.
      URL_PROPERTY = {
        type: 'string',
        format: 'uri',
        description: 'Source page URL'
      }.freeze

      # JSON Schema property for scrape/capture +strategy+.
      STRATEGY_PROPERTY = {
        type: 'string',
        enum: STRATEGIES,
        default: 'auto',
        description: 'Request strategy (auto runs faraday → botasaurus fallback chain)'
      }.freeze

      # JSON Schema property for inspect +strategy+ (auto stays on Faraday).
      INSPECT_STRATEGY_PROPERTY = STRATEGY_PROPERTY.merge(
        description: 'Request strategy (auto uses Faraday for cheap diagnostics; pin botasaurus when needed)'
      ).freeze

      # JSON Schema +oneOf+ requiring exactly one of +config+ or +yaml+.
      XOR_ONE_OF = [
        { required: %w[config], not: { required: %w[yaml] } }.freeze,
        { required: %w[yaml], not: { required: %w[config] } }.freeze
      ].freeze

      # JSON Schema properties for the config/yaml XOR pair.
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

      # Input schema for +validate_config+ (config XOR yaml).
      CONFIG_XOR_SCHEMA = {
        type: 'object',
        properties: CONFIG_XOR_PROPERTIES,
        oneOf: XOR_ONE_OF
      }.freeze

      # Input schema for +apply_config+ (required URL plus config XOR yaml).
      APPLY_INPUT_SCHEMA = {
        type: 'object',
        properties: { url: URL_PROPERTY, **CONFIG_XOR_PROPERTIES }.freeze,
        required: %w[url],
        oneOf: XOR_ONE_OF
      }.freeze

      # Input schema for +scrape_url+.
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

      # Input schema for +inspect_url+.
      INSPECT_INPUT_SCHEMA = {
        type: 'object',
        properties: { url: URL_PROPERTY, strategy: INSPECT_STRATEGY_PROPERTY }.freeze,
        required: %w[url]
      }.freeze

      # Input schema for +capture_config+.
      CAPTURE_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          url: URL_PROPERTY,
          strategy: STRATEGY_PROPERTY,
          items_selector: { type: 'string', description: 'Optional CSS selector hint for items' }
        }.freeze,
        required: %w[url]
      }.freeze

      # Input schema for +batch_inspect_urls+.
      BATCH_INSPECT_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          urls: {
            type: 'array',
            items: URL_PROPERTY,
            minItems: 1,
            maxItems: 25,
            description: 'List of page URLs to inspect (1..25)'
          }.freeze,
          strategy: INSPECT_STRATEGY_PROPERTY,
          concurrency: {
            type: 'integer',
            description: 'Max parallel worker threads (1..10, default: 5)',
            default: 5
          }
        }.freeze,
        required: %w[urls]
      }.freeze

      # Input schema for +batch_scrape_urls+.
      BATCH_SCRAPE_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          urls: {
            type: 'array',
            items: URL_PROPERTY,
            minItems: 1,
            maxItems: 25,
            description: 'List of page URLs to scrape (1..25)'
          }.freeze,
          strategy: STRATEGY_PROPERTY,
          limit: { type: 'integer', description: 'Max articles per URL to keep (default 10)', default: 10 },
          concurrency: {
            type: 'integer',
            description: 'Max parallel worker threads (1..10, default: 5)',
            default: 5
          }
        }.freeze,
        required: %w[urls]
      }.freeze

      # Input schema for +generate_catalog_config+.
      GENERATE_CATALOG_CONFIG_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          url: URL_PROPERTY,
          strategy: STRATEGY_PROPERTY,
          topics: {
            type: 'array',
            items: {
              type: 'string',
              enum: Config::Validator::DIRECTORY_TOPICS
            },
            description: 'Optional directory topics (from DIRECTORY_TOPICS vocabulary)'
          }.freeze,
          title: {
            type: 'string',
            description: 'Optional feed and directory title'
          },
          summary: {
            type: 'string',
            maxLength: 160,
            description: 'Optional directory summary (max 160 characters)'
          }
        }.freeze,
        required: %w[url]
      }.freeze

      # Input schema for +certify_config+.
      CERTIFY_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          **CONFIG_XOR_PROPERTIES,
          check_live_feed: {
            type: 'boolean',
            default: true,
            description: 'Whether to execute in-memory live feed generation and item quality checks'
          }
        }.freeze,
        oneOf: XOR_ONE_OF
      }.freeze

      # Tool annotations for open-world read-only tools.
      ANNOTATIONS_OPEN_WORLD = {
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: true
      }.freeze

      # Tool annotations for +validate_config+ (closed world).
      ANNOTATIONS_VALIDATE = ANNOTATIONS_OPEN_WORLD.merge(open_world_hint: false).freeze

      # Human titles for +tools/list+.
      TITLES = {
        scrape_url: 'Scrape URL',
        inspect_url: 'Inspect URL',
        capture_config: 'Capture feed config',
        validate_config: 'Validate feed config',
        apply_config: 'Apply feed config',
        batch_inspect_urls: 'Batch inspect URLs',
        batch_scrape_urls: 'Batch scrape URLs',
        generate_catalog_config: 'Generate catalog config',
        certify_config: 'Certify feed config'
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

        ##
        # Rejects unpublished MCP request adapters so apply/validate cannot
        # {File.read} arbitrary paths. CLI and Config still allow +local_file+.
        #
        # @param config [Hash]
        # @return [void]
        # @raise [UnpublishedRequestError] when +strategy+ is outside {STRATEGIES}
        #   or +request.local_file_path+ is present
        def assert_published_request!(config)
          strategy = config[:strategy]
          unless strategy.nil? || STRATEGIES.include?(strategy.to_s)
            raise UnpublishedRequestError,
                  "MCP does not accept strategy #{strategy} (published: #{STRATEGIES.join(', ')})"
          end
          return unless config.dig(:request, :local_file_path)

          raise UnpublishedRequestError, 'MCP does not accept request.local_file_path'
        end
      end
    end
  end
end
