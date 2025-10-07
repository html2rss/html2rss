# frozen_string_literal: true

require 'yaml'

module Html2rss
  ##
  # The provided configuration is used to generate the RSS feed.
  # This class provides methods to load and process configuration from a YAML file,
  # supporting both single and multiple feed configurations.
  #
  # Configuration is validated during initialization.
  class Config
    class InvalidConfig < Html2rss::Error; end

    class << self
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
      def load_yaml(file, feed_name = nil, multiple_feeds_key: MultipleFeedsConfig::CONFIG_KEY_FEEDS)
        raise ArgumentError, "File '#{file}' does not exist" unless File.exist?(file)
        raise ArgumentError, "`#{multiple_feeds_key}` is a reserved feed name" if feed_name == multiple_feeds_key

        yaml = YAML.safe_load_file(file, symbolize_names: true)

        return yaml unless yaml.key?(multiple_feeds_key)

        config = yaml.dig(multiple_feeds_key, feed_name.to_sym)
        raise ArgumentError, "Feed '#{feed_name}' not found under `#{multiple_feeds_key}` key." unless config

        MultipleFeedsConfig.to_single_feed(config, yaml, multiple_feeds_key:)
      end

      ##
      # Processes the provided configuration hash, applying dynamic parameters if given,
      # and returns a new configuration object.
      #
      # @param config [Hash<Symbol, Object>] the configuration hash.
      # @param params [Hash<Symbol, Object>, nil] dynamic parameters for string formatting.
      # @return [Html2rss::Config] the configuration object.
      def from_hash(config, params: nil)
        config = config.dup

        if params
          DynamicParams.call(config[:headers], params)
          DynamicParams.call(config[:channel], params)
          DynamicParams.call(config[:request], params)
        end

        new(config)
      end

      ##
      # Provides a default configuration.
      #
      # @return [Hash<Symbol, Object>] a hash with default configuration values.
      def default_config
        {
          strategy: RequestService.default_strategy_name,
          channel: { time_zone: 'UTC' },
          headers: {},
          request: {},
          stylesheets: []
        }
      end
    end

    ##
    # Initializes the configuration object.
    #
    # Processes deprecated attributes, applies default values, and validates the configuration.
    #
    # @param config [Hash<Symbol, Object>] the configuration hash.
    # @raise [InvalidConfig] if the configuration fails validation.
    def initialize(config) # rubocop:disable Metrics/AbcSize
      config = config.dup if config.frozen?

      config = handle_deprecated_channel_attributes(config)
      config = apply_default_config(config)
      config = apply_default_selectors_config(config) if config[:selectors]
      config = apply_default_auto_source_config(config) if config[:auto_source]

      validator = Validator.new.call(config)

      raise InvalidConfig, "Invalid configuration: #{validator.errors.to_h}" unless validator.success?

      @config = validator.to_h.freeze
    end

    def strategy = config[:strategy]
    def stylesheets = config[:stylesheets]

    def headers = config[:headers]
    def request_options = config[:request]

    def channel = config[:channel]
    def url = config.dig(:channel, :url)
    def time_zone = config.dig(:channel, :time_zone)

    def selectors = config[:selectors]
    def auto_source = config[:auto_source]

    private

    attr_reader :config

    def handle_deprecated_channel_attributes(config)
      { strategy: RequestService.default_strategy_name, headers: {} }.each_pair do |key, default_value|
        if !config[key] && (value = config.dig(:channel, key))
          Log.warn("The `channel.#{key}` key is deprecated. Please move the definition of `#{key}` to the top level.")
          config[key] = value
        end

        config[key] ||= default_value
      end

      config
    end

    def apply_default_config(config)
      deep_merge(self.class.default_config, config)
    end

    def apply_default_selectors_config(config)
      deep_merge({ selectors: Selectors::DEFAULT_CONFIG }, config)
    end

    def apply_default_auto_source_config(config)
      deep_merge({ auto_source: Html2rss::AutoSource::DEFAULT_CONFIG }, config)
    end

    def deep_merge(base_config, override_config)
      base_config.merge(override_config) do |_key, oldval, newval|
        oldval.is_a?(Hash) && newval.is_a?(Hash) ? deep_merge(oldval, newval) : newval
      end
    end
  end
end
