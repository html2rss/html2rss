# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Tracks runtime request controls together with whether each value was explicitly set.
    class RequestControls
      REQUEST_CONTROL_KEYS = %i[strategy max_redirects max_requests].freeze

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
      # @param config [Hash<Symbol, Object>, Hash<String, Object>] raw config input
      # @return [RequestControls] request controls extracted from the config hash
      def self.from_config(config)
        new(
          strategy: value_for(config, :strategy),
          max_redirects: value_for(config, :max_redirects),
          max_requests: value_for(config, :max_requests),
          explicit_keys: explicit_keys_for(config)
        )
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
        REQUEST_CONTROL_KEYS.each do |key|
          next unless explicit?(key)

          config[key] = public_send(key)
        end

        config
      end

      private

      attr_reader :explicit_keys

      def self.explicit_keys_for(config)
        REQUEST_CONTROL_KEYS.select do |key|
          config.key?(key) || config.key?(key.to_s)
        end
      end

      def self.value_for(config, key)
        return config[key] if config.key?(key)
        return config[key.to_s] if config.key?(key.to_s)

        nil
      end
    end
  end
end
