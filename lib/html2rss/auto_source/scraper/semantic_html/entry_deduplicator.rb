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
          # @param link_resolver [Scoring::LinkResolver, nil] page-scoped destination facts cache
          # @param time_zone [String, nil] channel time zone for naive leftover dates
          def initialize(url, scraper: nil, link_resolver: nil, time_zone: nil)
            @url = url
            @time_zone = time_zone
            @scraper = scraper
            @link_resolver = link_resolver || Scoring::LinkResolver.new(url)
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
              @article_cache[entry] =
                ::Html2rss::Html::SstArticleExtractor.call(entry, base_url: @url, scraper: @scraper,
                                                                  time_zone: @time_zone,
                                                                  link_resolver: @link_resolver)
            end
          end

          ##
          # @param left [Scoring::RankedSegment]
          # @param right [Scoring::RankedSegment]
          # @return [Boolean]
          def stronger_entry?(left, right) # rubocop:disable Metrics/AbcSize
            deltas = [left.final_score <=> right.final_score, left.quality_score <=> right.quality_score,
                      nesting_delta(left, right)]
            decisive = deltas.find { !_1.zero? }
            return decisive.positive? if decisive

            left_article = article_for(left)
            right_article = article_for(right)
            return !right_article if left_article.nil? || right_article.nil?

            richness_delta = payload_richness_signature(left_article) <=> payload_richness_signature(right_article)
            richness_delta.zero? ? left.position < right.position : richness_delta.positive?
          end

          private

          # On a score tie the card inside the other is the tighter one: the container around it also holds
          # its neighbours, whose text is no part of the story.
          #
          # @return [Integer] 1 when +left+ nests in +right+, -1 for the reverse, else 0
          def nesting_delta(left, right)
            inner = left.root_node
            outer = right.root_node
            return 0 if inner.equal?(outer)
            return 1 if SST::Index.descendant_or_self?(inner, outer)

            SST::Index.descendant_or_self?(outer, inner) ? -1 : 0
          end

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

          def word_count(text) = (@word_counts ||= {})[text] ||= WordCount.count(text)
        end
      end
    end
  end
end
