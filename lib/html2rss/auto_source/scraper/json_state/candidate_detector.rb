# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class JsonState
        # Identifies arrays that look like collections of article hashes.
        module CandidateDetector
          # Serialized anchor/menu attributes (link target, rel, nofollow flag, submenu) marking menu links.
          NAVIGATION_KEYS = %i[target rel noFollow children].freeze

          class << self
            # @param document [Hash, Array, Object] candidate document node
            # @return [Boolean] whether the node contains article-like arrays
            def candidate_array?(document)
              case document
              when Array
                return true if array_of_articles?(document)
                return false if menu_array?(document)

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

            # Accepts arrays of title+url hashes unless they form a menu (see {menu_array?}).
            #
            # @param array [Array<Object>] candidate list of entries
            # @return [Boolean] whether array holds title+url hashes that are mostly not menu links
            def array_of_articles?(array)
              array.any? { linked_entry?(_1) } && !menu_array?(array)
            end

            # Most title+url hashes are serialized menu links (see {navigation_link?}), so the array is an
            # SSR header/footer menu. Callers skip its whole subtree, including submenu `children` arrays.
            #
            # @param array [Array<Object>] candidate list of entries
            # @return [Boolean] whether more than half of the title+url hashes are menu links
            def menu_array?(array)
              linked = array.select { linked_entry?(_1) }
              linked.count { navigation_link?(_1) } * 2 > linked.size
            end

            # @param entry [Hash] entry with title and URL fields
            # @return [Boolean] whether the entry carries link-presentation keys and no description, image, or date
            def navigation_link?(entry)
              return false unless NAVIGATION_KEYS.any? { entry.key?(_1) }

              !(ValueFinder.fetch(entry, ArticleNormalizer::DESCRIPTION_KEYS) ||
                ValueFinder.fetch(entry, ArticleNormalizer::IMAGE_KEYS) ||
                ArticleNormalizer.published_at(entry))
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
