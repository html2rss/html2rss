# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Public class-level helpers for loading, validating, and exporting config.
    module ClassMethods
      UNSET = Object.new.freeze

      ##
      # Returns the exported JSON Schema for html2rss configuration.
      #
      # @return [Hash<String, Object>] JSON Schema represented as a Ruby hash
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
      # @param config [Hash<Symbol, Object>] the configuration hash
      # @param params [Hash<Symbol, Object>, Hash<String, Object>, nil] dynamic parameters for string formatting
      # @return [Dry::Validation::Result] validation result after defaults and deprecations are applied
      def validate(config, params: UNSET)
        prepared_config = prepare_for_validation(resolve_effective_config(config, params:))

        Validator.new.call(prepared_config)
      rescue DynamicParams::ParamsMissing => error
        prepared_config = prepare_for_validation(deep_dup(config))
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
      # @param params [Hash<Symbol, Object>, Hash<String, Object>, nil] dynamic parameters for string formatting
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
      # @return [Hash<Symbol, Object>] the configuration hash.
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
      # @param config [Hash<Symbol, Object>] the configuration hash.
      # @param params [Hash<Symbol, Object>, Hash<String, Object>, nil] dynamic parameters for string formatting.
      # @return [Html2rss::Config] the configuration object.
      def from_hash(config, params: UNSET)
        new(resolve_effective_config(config, params:))
      end

      ##
      # Provides a default configuration.
      #
      # @return [Hash<Symbol, Object>] a hash with default configuration values.
      def default_config
        {
          strategy: RequestService.default_strategy_name,
          channel: { time_zone: 'UTC' },
          headers: RequestHeaders.browser_defaults,
          stylesheets: []
        }
      end

      private

      def resolve_effective_config(config, params:)
        effective_config = deep_dup(config)
        resolved_params = parameter_defaults(effective_config)
        resolved_params.merge!(params) unless params.equal?(UNSET) || params.nil?

        DynamicParams.call(effective_config[:headers], resolved_params)
        DynamicParams.call(effective_config[:channel], resolved_params)

        effective_config
      end

      def parameter_defaults(config)
        config.fetch(:parameters, {}).each_with_object({}) do |(name, definition), defaults|
          next unless definition.is_a?(Hash) && definition.key?(:default)

          defaults[name] = definition[:default]
        end
      end

      def prepare_for_validation(config)
        allocate.send(:prepare_config, deep_dup(config))
      end

      # rubocop:disable Metrics/MethodLength
      def deep_dup(object)
        case object
        when Hash
          object.transform_values do |value|
            deep_dup(value)
          end
        when Array
          object.map { |value| deep_dup(value) }
        else
          begin
            object.dup
          rescue TypeError
            object
          end
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
