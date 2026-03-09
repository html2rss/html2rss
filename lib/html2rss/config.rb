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
  class Config
    class InvalidConfig < Html2rss::Error; end
    extend ClassMethods

    ##
    # Initializes the configuration object.
    #
    # Processes deprecated attributes, applies default values, and validates the configuration.
    #
    # @param config [Hash<Symbol, Object>] the configuration hash.
    # @raise [InvalidConfig] if the configuration fails validation.
    def initialize(config)
      prepared_config = prepare_config(config)

      validator = Validator.new.call(prepared_config)

      raise InvalidConfig, "Invalid configuration: #{validator.errors.to_h}" unless validator.success?

      validated_config = validator.to_h

      validated_config[:headers] = RequestHeaders.normalize(
        validated_config[:headers],
        channel_language: validated_config.dig(:channel, :language),
        url: validated_config.dig(:channel, :url)
      )

      @config = validated_config.freeze
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

    def prepare_config(config)
      config = config.dup if config.frozen?

      config = handle_deprecated_channel_attributes(config)
      config = apply_default_config(config)
      config = apply_default_selectors_config(config) if config[:selectors]
      config = apply_default_auto_source_config(config) if config[:auto_source]

      config
    end

    def deep_merge(base_config, override_config)
      base_config.merge(override_config) do |_key, oldval, newval|
        oldval.is_a?(Hash) && newval.is_a?(Hash) ? deep_merge(oldval, newval) : newval
      end
    end
  end
end
