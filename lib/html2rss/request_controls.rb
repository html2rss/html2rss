# frozen_string_literal: true

module Html2rss
  ##
  # Tracks runtime request controls together with whether each value was explicitly set.
  class RequestControls
    TOP_LEVEL_KEYS = %i[strategy].freeze
    REQUEST_KEYS = %i[max_redirects max_requests].freeze
    REQUEST_CONTROL_KEYS = (TOP_LEVEL_KEYS + REQUEST_KEYS).freeze

    ##
    # @param config [Hash<Symbol, Object>, Hash<String, Object>] raw config input
    # @return [RequestControls] request controls extracted from the config hash
    def self.from_config(config)
      new(
        strategy: value_for(config, :strategy),
        max_redirects: request_value_for(config, :max_redirects),
        max_requests: request_value_for(config, :max_requests),
        explicit_keys: explicit_keys_for(config)
      )
    end

    def self.explicit_keys_for(config)
      TOP_LEVEL_KEYS.filter { top_level_key?(config, _1) } +
        REQUEST_KEYS.filter { request_key?(config, _1) }
    end

    def self.value_for(config, key)
      return config[key] if config.key?(key)
      return config[key.to_s] if config.key?(key.to_s)

      nil
    end

    def self.request_value_for(config, key)
      request_config = value_for(config, :request)
      return nil unless request_config.is_a?(Hash)

      value_for(request_config, key)
    end

    def self.top_level_key?(config, key)
      config.key?(key) || config.key?(key.to_s)
    end

    def self.request_key?(config, key)
      request_config = value_for(config, :request)
      request_config.is_a?(Hash) && top_level_key?(request_config, key)
    end
    private_class_method :explicit_keys_for, :request_value_for, :top_level_key?, :request_key?, :value_for

    ##
    # @param strategy [Symbol, nil] effective request strategy
    # @param max_redirects [Integer, nil] effective redirect limit
    # @param max_requests [Integer, nil] effective request budget
    # @param explicit_keys [Array<Symbol>] controls explicitly supplied by the caller
    def initialize(strategy: nil, max_redirects: nil, max_requests: nil, explicit_keys: [])
      @strategy = strategy
      @max_redirects = max_redirects
      @max_requests = max_requests
      @explicit_keys = explicit_keys.map(&:to_sym).uniq.freeze
      freeze
    end

    ##
    # @return [Symbol, nil] effective request strategy
    attr_reader :strategy

    ##
    # @return [Integer, nil] effective redirect limit
    attr_reader :max_redirects

    ##
    # @return [Integer, nil] effective request budget
    attr_reader :max_requests

    ##
    # @param name [Symbol, String] request control name
    # @return [Boolean] whether the control was explicitly supplied
    def explicit?(name)
      explicit_keys.include?(name.to_sym)
    end

    ##
    # @param strategy [Symbol, nil] validated request strategy
    # @param max_redirects [Integer, nil] validated redirect limit
    # @param max_requests [Integer, nil] validated request budget
    # @return [RequestControls] controls updated with validated effective values
    def with_effective_values(strategy:, max_redirects:, max_requests:)
      self.class.new(
        strategy:,
        max_redirects:,
        max_requests:,
        explicit_keys:
      )
    end

    ##
    # Applies only explicitly set controls to the provided config hash.
    #
    # @param config [Hash<Symbol, Object>] mutable config hash
    # @return [Hash<Symbol, Object>] the same hash with explicit controls written
    def apply_to(config)
      config[:strategy] = strategy if explicit?(:strategy)
      apply_request_value(config, :max_redirects, max_redirects)
      apply_request_value(config, :max_requests, max_requests)
      config
    end

    private

    attr_reader :explicit_keys

    def apply_request_value(config, key, value)
      return unless explicit?(key)

      ensure_request_config!(config)
      config[:request][key] = value
    end

    def ensure_request_config!(config)
      request_config = config[:request]
      return config[:request] = {} if request_config.nil?
      return if request_config.is_a?(Hash)

      raise ArgumentError, 'request config must be a hash'
    end
  end
end
