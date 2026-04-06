# frozen_string_literal: true

module Html2rss
  # Shared helpers for hash normalization and structural operations.
  module HashUtil
    module_function

    # Deeply duplicates nested arrays and hashes.
    #
    # @param object [Object] nested value from configuration or runtime state
    # @return [Object] deep duplicated object
    def deep_dup(object)
      case object
      when Hash
        object.to_h { |key, value| [key, deep_dup(value)] }
      when Array
        object.map { deep_dup(_1) }
      else
        object.dup
      end
    rescue TypeError
      object
    end

    # Deeply merges nested hashes while replacing non-hash values from override.
    #
    # @param base [Hash] base hash
    # @param override [Hash] override hash
    # @return [Hash] merged hash
    def deep_merge(base, override)
      base.merge(override) do |_key, base_value, override_value|
        base_value.is_a?(Hash) && override_value.is_a?(Hash) ? deep_merge(base_value, override_value) : override_value
      end
    end

    # Converts string-keyed hashes to symbol-keyed hashes recursively.
    #
    # @param object [Object] value to normalize
    # @param context [String] error context
    # @return [Object] normalized value
    def deep_symbolize_keys(object, context: 'hash')
      case object
      when Hash
        object.to_h do |key, value|
          [symbol_key(key, context:), deep_symbolize_keys(value, context:)]
        end
      when Array
        object.map { deep_symbolize_keys(_1, context:) }
      else
        object
      end
    end

    # Validates that hash keys are symbols.
    #
    # @param value [Object] candidate hash container whose keys must be symbols
    # @param context [String] error context
    # @param deep [Boolean] whether nested hashes should also be validated
    # @return [void]
    def assert_symbol_keys!(value, context: 'hash', deep: true)
      return unless value.is_a?(Hash)

      key = value.keys.find { !_1.is_a?(Symbol) }
      raise ArgumentError, "#{context} must use symbol keys (found #{key.inspect})" if key
      return unless deep

      value.each_value { assert_symbol_keys!(_1, context:, deep:) }
    end

    # Validates that hash keys are strings.
    #
    # @param value [Object] candidate hash container whose keys must be strings
    # @param context [String] error context
    # @param deep [Boolean] whether nested hashes should also be validated
    # @return [void]
    def assert_string_keys!(value, context: 'hash', deep: true)
      return unless value.is_a?(Hash)

      key = value.keys.find { !_1.is_a?(String) }
      raise ArgumentError, "#{context} must use string keys (found #{key.inspect})" if key
      return unless deep

      value.each_value { assert_string_keys!(_1, context:, deep:) }
    end

    def symbol_key(key, context:)
      return key if key.is_a?(Symbol)
      return key.to_sym if key.is_a?(String)

      raise ArgumentError, "#{context} must use string or symbol keys (found #{key.inspect})"
    end
    private_class_method :symbol_key
  end
end
