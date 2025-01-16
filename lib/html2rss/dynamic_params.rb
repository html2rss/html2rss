# frozen_string_literal: true

module Html2rss
  ##
  # Applies the params recursively to the given value.
  class DynamicParams
    class ParamsMissing < Html2rss::Error; end

    class << self
      ##
      # Traverse the given value and replace the format string with the given params.
      #
      # @param value [String, Hash, Enumerable, Object]
      # @param params [Hash]
      # @return returns the Object with its Strings being formatted with the given params.
      def call(value, params = {}, getter: nil, replace_missing_with: nil) # rubocop:disable Metrics/MethodLength
        case value
        when String
          format_params = format_params(params, getter:, replace_missing_with:)

          begin
            format(value, format_params)
          rescue KeyError => error
            raise ParamsMissing, error.message if replace_missing_with.nil?
          end
        when Hash
          from_hash(value, params, getter:, replace_missing_with:)
        when Enumerable
          from_enumerable(value, params, getter:, replace_missing_with:)
        else
          value
        end
      end

      private

      def format_params(params, getter:, replace_missing_with:)
        Hash.new do |hash, key|
          hash[key] = if getter
                        getter.call(key)
                      else
                        params.fetch(key.to_sym) { params[key.to_s] }
                      end

          hash[key] ||= replace_missing_with if replace_missing_with
          hash[key]
        end
      end

      def from_hash(hash, params, getter:, replace_missing_with:)
        hash.transform_keys!(&:to_sym)
        hash.transform_values! { |value| call(value, params, getter:, replace_missing_with:) }
      end

      def from_enumerable(enumerable, params, getter:, replace_missing_with:)
        enumerable.map! { |value| call(value, params, getter:, replace_missing_with:) }
      end
    end
  end
end
