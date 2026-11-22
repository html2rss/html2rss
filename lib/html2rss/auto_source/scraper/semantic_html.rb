# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes semantic containers via SST: Normalizer → Segmenter → Scoring → SstArticleExtractor.
      class SemanticHtml
        include Enumerable

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

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @return [Boolean] true when at least one semantic container has an eligible anchor
        def self.articles?(parsed_body)
          return false unless parsed_body

          new(parsed_body, url: 'https://example.com').extractable?
        end

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML (when +document:+ omitted)
        # @param url [String, Html2rss::Url] base url
        # @param document [SST::Document, nil] memoized SST document from AutoSource
        # @param link_resolver [Scoring::LinkResolver, nil] shared page-scoped resolver
        def initialize(parsed_body = nil, url:, document: nil, link_resolver: nil)
          @parsed_body = parsed_body
          @provided_document = document
          @provided_link_resolver = link_resolver
          @url = url
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
            deduplicator = EntryDeduplicator.new(@url, scraper: self.class, link_resolver:)
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
            base_url: @url,
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

        def link_resolver
          @link_resolver ||= @provided_link_resolver || Scoring::LinkResolver.new(@url)
        end

        def document
          @document ||= @provided_document || SST::Normalizer.call(@parsed_body)
        end
      end
    end
  end
end
