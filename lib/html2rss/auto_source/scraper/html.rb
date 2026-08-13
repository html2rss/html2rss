# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Fallback HTML list/cluster scraper via SST pipeline
      # (Normalizer → Segmenter → Scoring::Engine → Extractor).
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

          new(parsed_body, url: DETECTION_BASE_URL).any?
        rescue ArgumentError
          false
        end

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML (when +document:+ omitted)
        # @param url [String, Html2rss::Url]
        # @param document [SST::Document, nil] memoized SST document from AutoSource
        # @param opts [Hash]
        # @option opts [Boolean] :fallback_anchorless keep anchorless cluster cards
        # @option opts [Integer] :minimum_selector_frequency list frequency floor
        # @option opts [Integer] :use_top_selectors list selector budget
        def initialize(parsed_body = nil, url:, document: nil, **opts)
          @document = document || SST::Normalizer.call(parsed_body)
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
          articles.any?
        end

        private

        def articles
          @articles ||= begin
            extracted = list_articles
            extracted += cluster_articles if @fallback_anchorless && extracted.empty?
            extracted
          end
        rescue ArgumentError
          []
        end

        def list_articles
          segments = Segmenter.call(
            @document,
            base_url: @url,
            strategy: :list,
            permit_unanchored: false,
            minimum_selector_frequency:,
            use_top_selectors:
          )
          materialize(engine.select_eligible(segments, limit: TOP_K))
        end

        def cluster_articles
          segments = Segmenter.call(
            @document,
            base_url: @url,
            strategy: :cluster,
            permit_unanchored: true,
            minimum_selector_frequency:
          )
          materialize(engine.select_eligible(segments, limit: TOP_K), fallback_anchorless: true)
        end

        def materialize(ranked, fallback_anchorless: false)
          ranked.filter_map do |entry|
            Extractor.call(entry, base_url: @url, scraper: self.class, fallback_anchorless:)
          end
        end

        def engine
          @engine ||= Scoring::Engine.new(link_resolver: Scoring::LinkResolver.new(@url))
        end

        def minimum_selector_frequency = @opts[:minimum_selector_frequency] || DEFAULT_MINIMUM_SELECTOR_FREQUENCY
        def use_top_selectors = @opts[:use_top_selectors] || DEFAULT_USE_TOP_SELECTORS
      end
    end
  end
end
