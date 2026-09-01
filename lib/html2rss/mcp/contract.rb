# frozen_string_literal: true

require 'digest'

module Html2rss
  module MCP
    ##
    # Published MCP contract: strategy enum, input/output schemas, listing
    # annotations, and the single compact JSON envelope response.
    module Contract # rubocop:disable Metrics/ModuleLength -- published listing constants stay co-located
      # Published MCP request strategies (excludes +local_file+).
      STRATEGIES = %w[auto faraday botasaurus].freeze

      # Bump when tool names, required inputs, or envelope semantics change (independent of gem +VERSION+).
      MCP_CONTRACT_VERSION = 2
      public_constant :MCP_CONTRACT_VERSION

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

      # Input schema for +validate+ (config XOR yaml).
      CONFIG_XOR_SCHEMA = {
        type: 'object',
        properties: CONFIG_XOR_PROPERTIES,
        oneOf: XOR_ONE_OF
      }.freeze

      # Input schema for +apply+ (required URL plus config XOR yaml).
      APPLY_INPUT_SCHEMA = {
        type: 'object',
        properties: { url: URL_PROPERTY, **CONFIG_XOR_PROPERTIES }.freeze,
        required: %w[url],
        oneOf: XOR_ONE_OF
      }.freeze

      # Input schema for +test+.
      TEST_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          **CONFIG_XOR_PROPERTIES,
          min_items: { type: 'integer', description: 'Minimum required items (default: 1)', default: 1 },
          strict_quality: {
            type: 'boolean',
            description: 'Fail when ship-quality audit thresholds are exceeded (default: false)',
            default: false
          },
          strategy: STRATEGY_PROPERTY
        }.freeze,
        oneOf: XOR_ONE_OF
      }.freeze

      # Input schema for +scrape+.
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

      # Input schema for +inspect+.
      INSPECT_INPUT_SCHEMA = {
        type: 'object',
        properties: { url: URL_PROPERTY, strategy: INSPECT_STRATEGY_PROPERTY }.freeze,
        required: %w[url]
      }.freeze

      # Input schema for +recon+.
      RECON_INPUT_SCHEMA = INSPECT_INPUT_SCHEMA

      # Input schema for +capture+.
      CAPTURE_INPUT_SCHEMA = {
        type: 'object',
        properties: {
          url: URL_PROPERTY,
          strategy: STRATEGY_PROPERTY,
          items_selector: { type: 'string', description: 'Optional CSS selector hint for items' },
          force: { type: 'boolean', description: 'Bypass native feed check', default: false },
          topics: {
            type: 'array',
            items: { type: 'string' },
            description: 'Directory topics override'
          }.freeze,
          title: { type: 'string', description: 'Channel title override' },
          summary: { type: 'string', description: 'Directory summary override' },
          enhance: { type: 'boolean', description: 'Force enhance on or off' },
          limit: { type: 'integer', description: 'Max articles to keep' },
          max_redirects: { type: 'integer', description: 'Optional redirect limit override' },
          max_requests: { type: 'integer', description: 'Optional request budget override' }
        }.freeze,
        required: %w[url]
      }.freeze

      ##
      # Shared JSON Schema for batch URL tools (+batch_scrape+, +batch_inspect+, +batch_recon+).
      #
      # @param urls_description [String] description for the +urls+ array property
      # @param strategy_property [Hash] strategy JSON Schema property
      # @param extra_properties [Hash] additional tool-specific properties (e.g. +limit+ on scrape)
      # @return [Hash]
      def self.batch_urls_input_schema(urls_description:, strategy_property:, extra_properties: {}) # rubocop:disable Metrics/MethodLength
        {
          type: 'object',
          properties: {
            urls: {
              type: 'array',
              items: URL_PROPERTY,
              minItems: 1,
              maxItems: 25,
              description: urls_description
            }.freeze,
            strategy: strategy_property,
            concurrency: {
              type: 'integer',
              description: 'Max parallel worker threads (1..10, default: 5)',
              default: 5
            },
            **extra_properties
          }.freeze,
          required: %w[urls]
        }
      end

      # Input schema for +batch_scrape+.
      BATCH_SCRAPE_INPUT_SCHEMA = batch_urls_input_schema(
        urls_description: 'List of page URLs to scrape (1..25)',
        strategy_property: STRATEGY_PROPERTY,
        extra_properties: {
          limit: { type: 'integer', description: 'Max articles per URL to keep (default 10)', default: 10 }
        }
      ).freeze

      # Input schema for +batch_inspect+.
      BATCH_INSPECT_INPUT_SCHEMA = batch_urls_input_schema(
        urls_description: 'List of page URLs to inspect (1..25)',
        strategy_property: INSPECT_STRATEGY_PROPERTY
      ).freeze

      # Input schema for +batch_recon+.
      BATCH_RECON_INPUT_SCHEMA = BATCH_INSPECT_INPUT_SCHEMA

      # Tool annotations for open-world read-only tools.
      ANNOTATIONS_OPEN_WORLD = {
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: true
      }.freeze

      # Tool annotations for +validate+ (closed world).
      ANNOTATIONS_VALIDATE = ANNOTATIONS_OPEN_WORLD.merge(open_world_hint: false).freeze

      # Human titles for +tools/list+.
      TITLES = {
        scrape: 'Scrape',
        inspect: 'Inspect',
        recon: 'Recon',
        batch_scrape: 'Batch scrape',
        batch_inspect: 'Batch inspect',
        batch_recon: 'Batch recon',
        capture: 'Capture',
        validate: 'Validate',
        apply: 'Apply',
        test: 'Test'
      }.freeze

      # @api private
      CATALOG_ENTRY_LINE = lambda do |entry|
        schema = entry.fetch(:input_schema)
        required = Array(schema[:required]).sort.join(',')
        one_of = Array(schema[:oneOf]).map { |branch| Array(branch[:required]).sort.join('+') }.sort.join('|')
        [entry.fetch(:name), required, one_of].reject(&:empty?).join(':')
      end.freeze

      class << self
        ##
        # Canonical MCP tool names in alphabetical order (same set as +tools/list+).
        #
        # @return [Array<String>]
        def catalog_tools
          Server::Tools::TOOLS.map { |entry| entry.fetch(:name) }.sort
        end

        ##
        # Stable fingerprint of published tools, required keys, and +oneOf+ branches.
        # Clients compare against a cached +tools/list+ to detect stale catalogs.
        # Bump {MCP_CONTRACT_VERSION} for envelope or breaking wire semantics only.
        #
        # @return [String] 16-char hex digest prefix
        def catalog_fingerprint
          lines = Server::Tools::TOOLS.sort_by { |entry| entry.fetch(:name) }.map(&CATALOG_ENTRY_LINE)
          Digest::SHA256.hexdigest(lines.join("\n")).slice(0, 16)
        end

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
        # +File.read+ arbitrary paths. CLI and Config still allow +local_file+.
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
