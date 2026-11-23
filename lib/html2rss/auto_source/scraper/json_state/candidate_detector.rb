# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Identifies arrays that look like collections of article hashes.
        module CandidateDetector
          class << self
            # @param document [Hash, Array, Object] candidate document node
            # @return [Boolean] whether the node contains article-like arrays
            def candidate_array?(document)
              case document
              when Array
                return true if array_of_articles?(document)

                document.any? { candidate_array?(_1) }
              when Hash then document.each_value.any? { candidate_array?(_1) }
              else false
              end
            end

            # @param array [Array<Object>] candidate list of entries
            # @return [Boolean] whether array holds at least one title+url hash
            def array_of_articles?(array)
              array.any? { linked_entry?(_1) }
            end

            private

            def linked_entry?(element)
              ArticleNormalizer.linked?(ArticleNormalizer.article_sources(element))
            end
          end
        end
      end
    end
  end
end
