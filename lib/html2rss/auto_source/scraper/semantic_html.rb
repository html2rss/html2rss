# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes semantic containers via SST: Normalizer → Segmenter → Scoring → Extractor.
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
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base url
        # @param opts [Hash] scraper-specific options
        # @option opts [Boolean] :fallback_anchorless whether to keep containers without a primary anchor
        def initialize(parsed_body, url:, **opts)
          @parsed_body = parsed_body
          @url = url
          @permit_unanchored = opts.fetch(:fallback_anchorless, false)
        end

        attr_reader :parsed_body

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
            deduplicator = EntryDeduplicator.new(@url, scraper: self.class)
            entries = deduplicator.call(ranked_segments)
            entries.filter_map { |ranked| deduplicator.article_for(ranked) }
          end
        end

        def ranked_segments
          @ranked_segments ||= begin
            document = SST::Normalizer.call(@parsed_body)
            segments = Segmenter.call(
              document,
              base_url: @url,
              strategy: :semantic,
              permit_unanchored: @permit_unanchored
            )
            link_resolver = Scoring::LinkResolver.new(@url)
            Scoring::Engine.new(link_resolver:).rank_top(segments, limit: TOP_K)
          end
        end
      end
    end
  end
end
