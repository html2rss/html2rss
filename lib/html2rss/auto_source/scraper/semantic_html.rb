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

        ##
        # @return [Symbol] config key used to enable or configure this scraper
        def self.options_key = :semantic_html

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @return [Boolean] true when at least one semantic container has an eligible anchor
        def self.articles?(parsed_body)
          return false unless parsed_body

          new(parsed_body, url: 'https://example.com').extractable?
        rescue ArgumentError
          false
        end

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML (when +document:+ omitted)
        # @param url [String, Html2rss::Url] base url
        # @param document [SST::Document, nil] memoized SST document from AutoSource
        # @param link_resolver [Scoring::LinkResolver, nil] shared page-scoped resolver
        # @param opts [Hash] scraper-specific options
        # @option opts [Boolean] :fallback_anchorless whether to keep containers without a primary anchor
        def initialize(parsed_body = nil, url:, document: nil, link_resolver: nil, **opts)
          @parsed_body = parsed_body
          @provided_document = document
          @provided_link_resolver = link_resolver
          @url = url
          @permit_unanchored = opts.fetch(:fallback_anchorless, false)
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
        rescue ArgumentError
          false
        end

        private

        def articles
          @articles ||= begin
            deduplicator = EntryDeduplicator.new(@url, scraper: self.class, link_resolver:)
            entries = deduplicator.call(ranked_segments)
            entries.filter_map { |ranked| deduplicator.article_for(ranked) }
          end
        rescue ArgumentError
          []
        end

        def ranked_segments
          @ranked_segments ||= begin
            segments = Segmenter.call(
              document,
              base_url: @url,
              strategy: :semantic,
              permit_unanchored: @permit_unanchored,
              link_resolver:
            )
            Scoring::Engine.new(link_resolver:).rank_top(segments, limit: TOP_K)
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
