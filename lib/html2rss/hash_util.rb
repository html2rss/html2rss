# frozen_string_literal: true

module Html2rss
  # Shared helpers for hash normalization and structural operations.
  module HashUtil
    class << self
      # Deeply duplicates nested arrays and hashes.
      #
      # @param object [Object] nested value from configuration or runtime state
      # @return [Object] deep duplicated object
      def deep_dup(object)
        case object
        in Hash
          object.transform_values { deep_dup(_1) }
        in Array
          object.map { deep_dup(_1) }
        else
          object.dup
        end
      end

      # Deeply merges nested hashes while replacing non-hash values from override.
      #
      # @param base [Hash] base hash
      # @param override [Hash] override hash
      # @return [Hash] merged hash
      def deep_merge(base, override)
        base.merge(override) do |_key, old_val, new_val|
          case [old_val, new_val]
          in [Hash, Hash]
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end

      # Converts string-keyed hashes to symbol-keyed hashes recursively.
      #
      # @param object [Object] value to normalize
      # @param context [String] error context
      # @return [Object] normalized value
      def deep_symbolize_keys(object, context: 'hash')
        case object
        in Hash
          object.each_with_object({}) do |(k, v), memo|
            memo[symbol_key(k, context:)] = deep_symbolize_keys(v, context:)
          end
        in Array
          object.map { deep_symbolize_keys(_1, context:) }
        else
          object
        end
      end

      # Converts hash keys (and Symbol values) to strings recursively.
      #
      # @param object [Object] value to normalize
      # @return [Object] normalized value with string keys
      def deep_stringify_keys(object)
        case object
        when Hash
          object.to_h { |key, value| [key.to_s, deep_stringify_keys(value)] }
        when Array
          object.map { deep_stringify_keys(_1) }
        when Symbol
          object.to_s
        else
          object
        end
      end

      # Validates that the keys of a hash are symbols. Nested hashes are not walked.
      #
      # @param value [Object] candidate hash whose keys must be symbols
      # @param context [String] error context
      # @return [void]
      def assert_symbol_keys!(value, context: 'hash')
        return unless value in Hash
        return if value.each_key.all?(Symbol)

        invalid_key = value.keys.find { _1.class != Symbol }
        raise InvalidOption, "#{context} must use symbol keys (found #{invalid_key.inspect})"
      end

      private

      def symbol_key(key, context:)
        case key
        in Symbol then key
        in String then key.to_sym
        else
          raise InvalidOption, "#{context} must use string or symbol keys (found #{key.inspect})"
        end
      end
    end
  end
end
