# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class SemanticHtml
        ##
        # Collapses nested containers and deduplicates ranked segments pointing to the same destination.
        class EntryDeduplicator
          # @param url [String, Html2rss::Url] base url used to resolve relative hrefs
          # @param scraper [Class, nil] scraper class stamped onto extracted articles
          def initialize(url, scraper: nil)
            @url = url
            @scraper = scraper
            @link_resolver = Scoring::LinkResolver.new(url)
            @article_cache = {}.compare_by_identity
          end

          ##
          # @param ranked [Array<Scoring::RankedSegment>]
          # @return [Array<Scoring::RankedSegment>]
          def call(ranked)
            destination_groups(ranked).filter_map do |group|
              group.reduce do |best, entry|
                stronger_entry?(entry, best) ? entry : best
              end
            end
          end

          ##
          # @param entry [Scoring::RankedSegment]
          # @return [Html2rss::Article, nil]
          def article_for(entry)
            @article_cache.fetch(entry) do
              @article_cache[entry] = Extractor.call(
                entry,
                base_url: @url,
                scraper: @scraper,
                fallback_anchorless: true
              )
            end
          end

          ##
          # @param left [Scoring::RankedSegment]
          # @param right [Scoring::RankedSegment]
          # @return [Boolean]
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

          def entry_destination(entry)
            if entry.primary_link
              @link_resolver.destination_facts(entry.primary_link)&.destination
            else
              article_for(entry)&.url&.to_s
            end
          end

          def payload_richness_signature(article)
            [
              article.published_at ? 1 : 0,
              word_count(article.description),
              article.image ? 1 : 0,
              article.categories.length,
              article.enclosures.length
            ]
          end

          def word_count(text)
            (@word_counts ||= {})[text] ||= text.to_s.scan(/\p{Alnum}+/).size
          end
        end
      end
    end
  end
end
