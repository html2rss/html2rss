# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Fallback HTML list/cluster scraper via SST pipeline
      # (Normalizer → Segmenter → Scoring::Engine → Html::SstArticleExtractor).
      class Html
        include Enumerable

        # Absolute base URL used when probe-time detection needs to normalize relative hrefs.
        DETECTION_BASE_URL = 'https://example.com'
        # Minimum selector frequency required to treat a path as a stable list signal.
        DEFAULT_MINIMUM_SELECTOR_FREQUENCY = 2
        # Number of most frequent selectors kept for container extraction.
        DEFAULT_USE_TOP_SELECTORS = 5
        # Maximum articles materialized after eligibility filtering.
        TOP_K = Scoring::Engine::TOP_K

        ##
        # @return [Symbol]
        def self.options_key = :html

        ##
        # @param parsed_body [Nokogiri::HTML::Document]
        # @return [Boolean]
        def self.articles?(parsed_body)
          return false unless parsed_body

          new(parsed_body, url: DETECTION_BASE_URL).extractable?
        rescue ArgumentError
          false
        end

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML (when +document:+ omitted)
        # @param url [String, Html2rss::Url]
        # @param document [SST::Document, nil] memoized SST document from AutoSource
        # @param link_resolver [Scoring::LinkResolver, nil] shared page-scoped resolver
        # @param opts [Hash]
        # @option opts [Boolean] :fallback_anchorless keep anchorless cluster cards
        # @option opts [Integer] :minimum_selector_frequency list frequency floor
        # @option opts [Integer] :use_top_selectors list selector budget
        def initialize(parsed_body = nil, url:, document: nil, link_resolver: nil, **opts)
          @parsed_body = parsed_body
          @provided_document = document
          @provided_link_resolver = link_resolver
          @url = url
          @opts = opts
          @fallback_anchorless = opts.fetch(:fallback_anchorless, false)
        end

        ##
        # @yieldparam article [Html2rss::Article]
        # @return [Enumerator]
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
            ranked = list_ranked
            if ranked.empty? && @fallback_anchorless
              materialize(cluster_ranked, fallback_anchorless: true)
            else
              materialize(ranked)
            end
          end
        rescue ArgumentError
          []
        end

        def ranked_segments
          @ranked_segments ||= begin
            ranked = list_ranked
            ranked = cluster_ranked if @fallback_anchorless && ranked.empty?
            ranked
          end
        end

        def list_ranked
          @list_ranked ||= rank_strategy(:list, permit_unanchored: false)
        end

        def cluster_ranked
          @cluster_ranked ||= rank_strategy(:cluster, permit_unanchored: true)
        end

        def rank_strategy(strategy, permit_unanchored:)
          segments = Segmenter.call(
            document,
            base_url: @url,
            strategy:,
            permit_unanchored:,
            minimum_selector_frequency:,
            use_top_selectors:,
            link_resolver:
          )
          engine.select_eligible(segments, limit: TOP_K)
        end

        def materialize(ranked, fallback_anchorless: false)
          ranked.filter_map do |entry|
            ::Html2rss::Html::SstArticleExtractor.call(entry, base_url: @url, scraper: self.class, fallback_anchorless:)
          end
        end

        def engine
          @engine ||= Scoring::Engine.new(link_resolver:)
        end

        def link_resolver
          @link_resolver ||= @provided_link_resolver || Scoring::LinkResolver.new(@url)
        end

        def document
          @document ||= @provided_document || SST::Normalizer.call(@parsed_body)
        end

        def minimum_selector_frequency = @opts[:minimum_selector_frequency] || DEFAULT_MINIMUM_SELECTOR_FREQUENCY
        def use_top_selectors = @opts[:use_top_selectors] || DEFAULT_USE_TOP_SELECTORS
      end
    end
  end
end
