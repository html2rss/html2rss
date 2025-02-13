# frozen_string_literal: true

require 'yaml'

module Html2rss
  ##
  # The provided configuration is used to generate the RSS feed.
  # This class provides a method to load the configuration from a YAML file which
  # can contain either a single or multiple feed configurations.
  #
  # The provided configration is validated during initialization.
  class Config
    class << self
      ##
      # Returns the feed configuration from the YAML file.
      #
      # It supports multiple feeds under the feeds: key and a single feed configurations.
      #
      # @param file [String] the YAML file.
      # @param feed_name [String] the feed name (only when feeds: is present).
      # @return [Hash<Symbol, Object>] the configuration.
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
      # Returns the configuration object from the provided hash.
      # It also processes the dynamic parameters if provided.
      #
      # @param config [Hash<Symbol, Object>] the configuration.
      # @param params [Hash<Symbol, Object>] the dynamic parameters.
      # @return [Html2rss::Config] the configuration object.
      def from_hash(config, params: nil)
        if params
          DynamicParams.call(config[:headers], params)
          DynamicParams.call(config[:channel], params)
        end

        new(config)
      end

      def default_config
        {
          strategy: RequestService.default_strategy_name,
          channel: { time_zone: 'UTC' },
          headers: {},
          stylesheets: []
        }
      end
    end

    def initialize(config)
      config = handle_deprecated_channel_attributes(config)
      config = apply_default_config(config)
      config = apply_default_auto_source_config(config) if config[:auto_source]

      validator = Validator.new.call(config)

      raise ArgumentError, "Invalid configuration: #{validator.errors.to_h}" unless validator.success?

      @config = validator.to_h
    end

    def strategy = config[:strategy]
    def stylesheets = config[:stylesheets]

    def headers = config[:headers]

    def channel = config[:channel]
    def url = config.dig(:channel, :url)
    def time_zone = config.dig(:channel, :time_zone)

    def selectors = config[:selectors]
    def auto_source = config[:auto_source]

    private

    attr_reader :config

    def handle_deprecated_channel_attributes(config)
      { strategy: RequestService.default_strategy_name, headers: {} }.each_pair do |key, default_value|
        if !config[key] && (values = config.dig(:channel, key))
          Log.warn("The `channel.#{key}` key is deprecated. Please move definition of `#{key}` up to top level.")
          config[key] = values
        end

        config[key] ||= default_value
      end

      config
    end

    def apply_default_config(config)
      deep_merge(self.class.default_config, config)
    end

    def apply_default_auto_source_config(config)
      deep_merge({ auto_source: Html2rss::AutoSource::DEFAULT_CONFIG }, config)
    end

    def deep_merge(hash1, hash2)
      hash1.merge(hash2) do |_key, oldval, newval|
        oldval.is_a?(Hash) && newval.is_a?(Hash) ? deep_merge(oldval, newval) : newval
      end
    end
  end
end
