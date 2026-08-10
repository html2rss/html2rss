# frozen_string_literal: true

require 'json'
require 'yaml'

module Html2rss
  ##
  # The provided configuration is used to generate the RSS feed.
  # This class provides methods to load and process configuration from a YAML file,
  # supporting both single and multiple feed configurations.
  #
  # Configuration is validated during initialization.
  class Config # rubocop:disable Metrics/ClassLength
    # Raised when a configuration hash fails runtime validation.
    class InvalidConfig < Html2rss::Error; end
    # Sentinel to differentiate omitted params from explicit `nil`.
    UNSET = Object.new.freeze

    class << self
      ##
      # Returns the exported JSON Schema for html2rss configuration.
      #
      # @return [Hash{String => Object}] JSON Schema represented as a Ruby hash
      def json_schema
        Schema.json_schema
      end

      ##
      # Returns the exported JSON Schema as JSON.
      #
      # @param pretty [Boolean] whether to pretty-print the JSON output
      # @return [String] serialized JSON Schema
      def json_schema_json(pretty: true)
        pretty ? JSON.pretty_generate(json_schema) : JSON.generate(json_schema)
      end

      ##
      # Validates a configuration hash with the runtime validator.
      #
      # @param config [Hash{Symbol => Object}] the configuration hash
      # @param params [Hash{Symbol => Object, Hash{String => Object, nil}}] dynamic parameters for string formatting
      # @return [Dry::Validation::Result] validation result after defaults and deprecations are applied
      def validate(config, params: UNSET)
        prepared_config = prepare_for_validation(resolve_effective_config(config, params:))

        Validator.new.call(prepared_config)
      rescue DynamicParams::ParamsMissing => error
        prepared_config = prepare_for_validation(HashUtil.deep_symbolize_keys(config, context: 'config'))
        prepared_config[:dynamic_params_error] = error.message

        Validator.new.call(prepared_config)
      end

      ##
      # Returns the packaged JSON Schema file path.
      #
      # @return [String] absolute path to the packaged JSON Schema file
      def schema_path
        Schema.path
      end

      ##
      # Loads and validates a YAML configuration file.
      #
      # @param file [String] the YAML file to load
      # @param feed_name [String, nil] optional feed name for multi-feed files
      # @param multiple_feeds_key [Symbol] key under which multiple feeds are defined
      # @param params [Hash{Symbol => Object, Hash{String => Object, nil}}] dynamic parameters for string formatting
      # @return [Dry::Validation::Result] validation result after defaults and deprecations are applied
      def validate_yaml(file, feed_name = nil, multiple_feeds_key: MultipleFeedsConfig::CONFIG_KEY_FEEDS, params: UNSET)
        validate(load_yaml(file, feed_name, multiple_feeds_key:), params:)
      end

      ##
      # Loads the feed configuration from a YAML file.
      #
      # Supports multiple feeds defined under the specified key (default :feeds).
      #
      # @param file [String] the YAML file to load.
      # @param feed_name [String, nil] the feed name when using multiple feeds.
      # @param multiple_feeds_key [Symbol] the key under which multiple feeds are defined.
      # @return [Hash{Symbol => Object}] the configuration hash.
      # @raise [ArgumentError] if the file doesn't exist or feed is not found.
      # rubocop:disable Metrics/MethodLength
      def load_yaml(file, feed_name = nil, multiple_feeds_key: MultipleFeedsConfig::CONFIG_KEY_FEEDS)
        raise ArgumentError, "File '#{file}' does not exist" unless File.exist?(file)
        raise ArgumentError, "`#{multiple_feeds_key}` is a reserved feed name" if feed_name == multiple_feeds_key

        yaml = YAML.safe_load_file(file, symbolize_names: true)

        return yaml unless yaml.key?(multiple_feeds_key)

        unless feed_name
          available_feeds = yaml.fetch(multiple_feeds_key).keys.join(', ')
          raise ArgumentError,
                "Feed name is required under `#{multiple_feeds_key}`. Available feeds: #{available_feeds}"
        end

        config = yaml.dig(multiple_feeds_key, feed_name.to_sym)
        raise ArgumentError, "Feed '#{feed_name}' not found under `#{multiple_feeds_key}` key." unless config

        MultipleFeedsConfig.to_single_feed(config, yaml, multiple_feeds_key:)
      end
      # rubocop:enable Metrics/MethodLength

      ##
      # Processes the provided configuration hash, applying dynamic parameters if given,
      # and returns a new configuration object.
      #
      # @param config [Hash{Symbol => Object}] the configuration hash.
      # @param params [Hash{Symbol => Object, Hash{String => Object, nil}}] dynamic parameters for string formatting.
      # @return [Html2rss::Config] the configuration object.
      def from_hash(config, params: UNSET)
        new(resolve_effective_config(config, params:))
      end

      ##
      # Builds a top-level auto-source feed config for the public shortcut APIs.
      #
      # @param url [String] source page URL
      # @param items_selector [String, nil] optional selector hint for item extraction
      # @param request_controls [Html2rss::Config::RequestControls, nil] explicit request controls to write
      # @return [Hash{Symbol => Object}] feed config hash ready for {from_hash}
      def auto_source_config(url:, items_selector: nil, request_controls: nil)
        config = {
          channel: default_config[:channel].merge(url:),
          auto_source: AutoSource::DEFAULT_CONFIG
        }

        request_controls ||= RequestControls.new
        request_controls.apply_to(config)

        config[:selectors] = { items: { selector: items_selector, enhance: true } } if items_selector
        config
      end

      ##
      # Provides a default configuration.
      #
      # @return [Hash{Symbol => Object}] a hash with default configuration values.
      def default_config
        {
          strategy: default_strategy_name,
          request: default_request_config,
          channel: { time_zone: 'UTC' },
          headers: RequestHeaders.browser_defaults,
          stylesheets: Html2rss.defaults.stylesheets || []
        }
      end

      # @return [Symbol] the default feed-level strategy plan (+:auto+ or concrete)
      def default_strategy_name
        Html2rss.defaults.default_strategy || :auto
      end

      private

      def default_request_config
        {
          max_redirects: RequestService::Policy::DEFAULTS[:max_redirects],
          max_requests: RequestService::Policy::DEFAULTS[:max_requests],
          total_timeout_seconds: RequestService::Policy::DEFAULTS[:total_timeout_seconds]
        }
      end

      def resolve_effective_config(config, params:)
        effective_config = HashUtil.deep_symbolize_keys(config, context: 'config')
        resolved_params = parameter_defaults(effective_config)
        unless params.equal?(UNSET) || params.nil?
          resolved_params.merge!(HashUtil.deep_symbolize_keys(params, context: 'params'))
        end

        effective_config[:headers] = DynamicParams.call(effective_config[:headers], resolved_params)
        effective_config[:channel] = DynamicParams.call(effective_config[:channel], resolved_params)

        effective_config
      end

      def parameter_defaults(config)
        config.fetch(:parameters, {})
              .filter_map do |name, definition|
                [name, definition[:default]] if definition.is_a?(Hash) && definition.key?(:default)
              end
              .to_h
      end

      def prepare_for_validation(config)
        Config::Preparer.new.call(HashUtil.deep_dup(config))
      end
    end

    ##
    # Initializes the configuration object.
    #
    # Processes deprecated attributes, applies default values, and validates the configuration.
    #
    # @param config [Hash{Symbol => Object}] the configuration hash.
    # @raise [InvalidConfig] if the configuration fails validation.
    def initialize(config)
      @request_controls = RequestControls.from_config(config)
      prepared_config = Preparer.new.call(config)
      validated_config = validated_config_for(prepared_config)

      @config = validated_config.freeze
      @request_controls = request_controls.with_effective_values(
        strategy: validated_config[:strategy],
        max_redirects: validated_config.dig(:request, :max_redirects),
        max_requests: validated_config.dig(:request, :max_requests),
        total_timeout_seconds: validated_config.dig(:request, :total_timeout_seconds)
      )
    end

    # @return [Symbol, nil] selected request strategy
    def strategy = request_controls.strategy
    # @return [Integer, nil] configured redirect budget
    def max_redirects = request_controls.max_redirects
    # @return [Integer, nil] configured request budget
    def max_requests = request_controls.max_requests
    # @return [Integer, nil] configured request timeout
    def total_timeout_seconds = request_controls.total_timeout_seconds
    # @return [Array<Hash>] stylesheet definitions
    def stylesheets = config[:stylesheets]

    ##
    # @return [Boolean] whether max_requests was explicitly configured by the caller
    def explicit_max_requests?
      request_controls.explicit?(:max_requests)
    end

    ##
    # @return [Html2rss::Config::RequestControls] request controls with provenance
    attr_reader :request_controls

    # @return [Hash{String => String}] normalized HTTP headers
    def headers = config[:headers]
    # @return [Hash{Symbol => Object}] channel configuration
    def channel = config[:channel]
    # @return [String] source channel URL
    def url = config.dig(:channel, :url)
    # @return [String, nil] configured channel time zone
    def time_zone = config.dig(:channel, :time_zone)

    # @return [Hash{Symbol => Object}] request envelope configuration
    def request = config[:request]

    # @return [Hash{Symbol => Object, nil}] selectors configuration
    def selectors = config[:selectors]
    # @return [Hash{Symbol => Object, nil}] auto-source configuration
    def auto_source = config[:auto_source]

    private

    attr_reader :config

    # Normalizes raw config input before validation.
    class Preparer
      ##
      # @param config [Hash{Symbol => Object}] raw config input
      # @return [Hash{Symbol => Object}] config with defaults and deprecations applied
      def call(config)
        config = config.dup if config.frozen?

        config = handle_deprecated_channel_attributes(config)
        config = apply_default_config(config)
        config = apply_default_selectors_config(config) if config[:selectors]
        config = apply_default_auto_source_config(config) if config[:auto_source]

        config
      end

      private

      def handle_deprecated_channel_attributes(config)
        { strategy: Config.default_strategy_name, headers: {} }.each_pair do |key, default_value|
          if !config[key] && (value = config.dig(:channel, key))
            Log.warn("The `channel.#{key}` key is deprecated. Please move the definition of `#{key}` to the top level.")
            config[key] = value
          end

          config[key] ||= default_value
        end

        config
      end

      def apply_default_config(config)
        HashUtil.deep_merge(Config.default_config, config)
      end

      def apply_default_selectors_config(config)
        HashUtil.deep_merge({ selectors: Selectors::DEFAULT_CONFIG }, config)
      end

      def apply_default_auto_source_config(config)
        HashUtil.deep_merge({ auto_source: Html2rss::AutoSource::DEFAULT_CONFIG }, config)
      end
    end

    def validated_config_for(config)
      validator = Validator.new.call(config)

      raise InvalidConfig, "Invalid configuration: #{validator.errors.to_h}" unless validator.success?

      normalized_headers(validator.to_h)
    end

    def normalized_headers(validated_config)
      validated_config[:headers] = RequestHeaders.normalize(
        validated_config[:headers],
        channel_language: validated_config.dig(:channel, :language),
        url: validated_config.dig(:channel, :url)
      )
      validated_config
    end
  end
end
