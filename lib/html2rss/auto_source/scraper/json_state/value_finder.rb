# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Retrieves values from heterogeneous objects by probing multiple keys.
        module ValueFinder
          module_function

          # @param object [Hash, Array] candidate container traversed during key lookup
          # @param keys [Array<Symbol>] keys to probe in order
          # @return [Object, nil] first matching value
          def fetch(object, keys)
            case object
            when Hash then fetch_from_hash(object, keys)
            when Array then fetch_from_array(object, keys)
            end
          end

          # @param hash [Hash] hash candidate traversed during key lookup
          # @param keys [Array<Symbol>] keys to probe in order
          # @return [Object, nil] first matching value from hash or nested metadata
          def fetch_from_hash(hash, keys)
            keys.each do |key|
              return hash[key] if hash.key?(key)
            end

            fetch_nested(hash[:attributes], keys) ||
              fetch_nested(hash[:data], keys)
          end

          # @param array [Array] array whose entries may contain target keys
          # @param keys [Array<Symbol>] keys to probe in order
          # @return [Object, nil] first matching value from array entries
          def fetch_from_array(array, keys)
            array.each do |entry|
              result = fetch(entry, keys)
              return result if result
            end

            nil
          end

          # @param value [Hash, Array, nil] nested value to recurse into
          # @param keys [Array<Symbol>] keys to probe in order
          # @return [Object, nil] matching nested value
          def fetch_nested(value, keys)
            fetch(value, keys) if value
          end
        end
      end
    end
  end
end
