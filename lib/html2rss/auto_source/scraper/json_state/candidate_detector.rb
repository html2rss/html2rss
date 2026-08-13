# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Identifies arrays that look like collections of article hashes.
        module CandidateDetector
          # Preferred keys when extracting title-like values from state payloads.
          TITLE_KEYS = %i[title headline name text].freeze
          # Preferred keys when extracting URL-like values from state payloads.
          URL_KEYS = %i[url link href permalink slug path canonicalUrl shortUrl].freeze

          module_function

          # @param document [Hash, Array, Object] candidate document node
          # @return [Boolean] whether the node contains article-like arrays
          def candidate_array?(document)
            case document
            when Array
              return true if array_of_articles?(document)

              document.any? { traversable_candidate?(_1) }
            when Hash then document.each_value.any? { candidate_array?(_1) }
            else false
            end
          end

          # @param value [Hash, Array, Object] candidate nested value
          # @return [Boolean] whether nested value should be traversed for article candidates
          def traversable_candidate?(value)
            case value
            when Array, Hash then candidate_array?(value)
            else false
            end
          end

          # @param array [Array<Object>] candidate list of entries
          # @return [Boolean] whether array includes hash entries with title and URL fields
          def array_of_articles?(array)
            array.any? do |element|
              next unless element.is_a?(Hash)

              title_from(element) && url_from(element)
            end
          end

          # @param object [Hash] article candidate object
          # @return [Object, nil] detected title-like value
          def title_from(object)
            ValueFinder.fetch(object, TITLE_KEYS)
          end

          # @param object [Hash] article candidate object
          # @return [Object, nil] detected URL-like value
          def url_from(object)
            ValueFinder.fetch(object, URL_KEYS)
          end
        end
      end
    end
  end
end
