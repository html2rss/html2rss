# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes semantic containers via SST: Normalizer → Segmenter → Scoring → ArticleExtractor.
      class SemanticHtml < PageCards
        # Maximum articles materialized after ranking.
        TOP_K = Scoring::Engine::TOP_K
        # Score bonus per doubling of the repeated-card group size.
        GROUP_BONUS_PER_DOUBLING = 3.0
        # Ceiling of the repeated-card group score bonus.
        GROUP_BONUS_CAP = 15.0

        ##
        # @return [Symbol] config key used to enable or configure this scraper
        def self.options_key = :semantic_html

        ##
        # @param _opts [Hash] unused options
        # @return [Integer]
        def self.request_slots(_opts = {}) = 0

        ##
        # A bounded score bonus for the size of the repeated-card group a segment belongs to: the main
        # list is the largest group, so it outranks a rail or topical module of similar score, while a
        # large group of low-scoring cards (menu entries) never outranks real stories.
        #
        # @param group_size [Integer]
        # @return [Float]
        def self.group_bonus(group_size)
          [GROUP_BONUS_CAP, GROUP_BONUS_PER_DOUBLING * Math.log2(group_size)].min
        end

        ##
        # @yieldparam article [Html2rss::Article]
        # @return [Enumerator<Html2rss::Article>]
        def each
          return enum_for(:each) unless block_given?

          articles.each { yield _1 }
        end

        ##
        # @return [Boolean]
        def extractable?
          ranked_segments.any?
        end

        private

        def articles
          @articles ||= begin
            deduplicator = EntryDeduplicator.new(url, scraper: self.class, link_resolver:, time_zone:)
            entries = deduplicator.call(ranked_segments)
            entries.filter_map { |ranked| deduplicator.article_for(ranked) }
          end
        end

        def ranked_segments
          @ranked_segments ||= document ? rank_document : []
        end

        def rank_document
          segments = Segmenter.call(
            document,
            base_url: url,
            strategy: :semantic,
            link_resolver:
          )
          ranked = Scoring::Engine.new(link_resolver:).rank_top(segments, limit: segments.size)
          group_ranked(ranked).first(TOP_K)
        end

        # Score plus group bonus, document order on ties; the bonus lets the main list lead.
        def group_ranked(ranked)
          ranked.sort_by.with_index do |entry, rank|
            [-(entry.final_score + self.class.group_bonus(entry.segment.group_size)), rank]
          end
        end
      end
    end
  end
end
