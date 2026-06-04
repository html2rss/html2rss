# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class SemanticHtml
        ##
        # Collapses nested containers and deduplicates entries pointing to the same destination.
        # It resolves ties using scoring precedence and payload richness comparison.
        class Deduplicator
          # @param url [String, Html2rss::Url] base url used to resolve relative hrefs
          # @param extractor [Class] extractor class used to materialize articles
          def initialize(url, extractor)
            @url = url
            @extractor = extractor
            @article_cache = {}.compare_by_identity
          end

          # Collapses and deduplicates the given entries.
          #
          # @param entries [Array<Entry>] list of scraper entries
          # @return [Array<Entry>] deduplicated list of scraper entries
          def call(entries)
            destination_groups(entries).filter_map do |group|
              collapsed_group = collapse_nested_destination_group(group)
              collapsed_group.reduce do |best, entry|
                stronger_entry?(entry, best) ? entry : best
              end
            end
          end

          # Returns the materialized article hash for the entry, using the cache.
          #
          # @param entry [Entry] scraper entry
          # @return [Hash, nil] article payload
          def article_for(entry)
            return entry.article if entry.article

            @article_cache.fetch(entry) do
              @article_cache[entry] = @extractor.new(
                entry.container, base_url: @url, selected_anchor: entry.selected_anchor
              ).call
            end
          end

          # Compares two entries to determine which is stronger.
          #
          # @param left [Entry] left entry
          # @param right [Entry] right entry
          # @return [Boolean] true if left is stronger than right
          def stronger_entry?(left, right) # rubocop:disable Metrics/AbcSize
            final_delta = left.final_score <=> right.final_score
            return final_delta.positive? unless final_delta.zero?

            quality_delta = left.quality_score <=> right.quality_score
            return quality_delta.positive? unless quality_delta.zero?

            left_article = article_for(left)
            right_article = article_for(right)
            return !right_article if left_article.nil? || right_article.nil?

            richness_delta = payload_richness_signature(left_article) <=> payload_richness_signature(right_article)
            richness_delta.zero? ? left.position < right.position : richness_delta.positive?
          end

          private

          def destination_groups(entries) = entries.group_by { entry_destination(_1) }.values

          def collapse_nested_destination_group(entries)
            return entries if entries.size <= 1

            entries.reject do |entry|
              entries.any? do |other|
                next if entry.equal?(other)
                next unless nested_container_pair?(entry.container, other.container)

                stronger_entry?(other, entry)
              end
            end
          end

          def nested_container_pair?(left, right) = left.ancestors.include?(right) || right.ancestors.include?(left)

          def entry_destination(entry) = entry.destination_facts&.destination || article_for(entry)&.[](:url)&.to_s

          def payload_richness_signature(article)
            [
              article[:published_at] ? 1 : 0,
              word_count(article[:description]),
              article[:image] ? 1 : 0,
              Array(article[:categories]).length,
              Array(article[:enclosures]).length
            ]
          end

          def word_count(text) = text.to_s.scan(/\p{Alnum}+/).size
        end
      end
    end
  end
end
