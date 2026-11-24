# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Fallback HTML list scraper via SST pipeline
      # (Normalizer → Segmenter → Scoring::Engine → Html::SstArticleExtractor).
      class Html < PageCards
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
        # @param _opts [Hash] unused options
        # @return [Integer]
        def self.request_slots(_opts = {}) = 0

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML (when +document:+ omitted)
        # @param url [String, Html2rss::Url] page URL used to resolve relative links
        # @param document [SST::Document, nil] memoized SST document from AutoSource
        # @param link_resolver [Scoring::LinkResolver, nil] shared page-scoped resolver
        # @param opts [Hash]
        # @option opts [Integer] :minimum_selector_frequency list frequency floor
        # @option opts [Integer] :use_top_selectors list selector budget
        def initialize(parsed_body = nil, url:, document: nil, link_resolver: nil, **opts)
          super(parsed_body, url:, document:, link_resolver:)
          @opts = opts
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
        end

        private

        def articles
          @articles ||= materialize(ranked_segments)
        end

        def ranked_segments
          @ranked_segments ||= if document
                                 segments = Segmenter.call(document, base_url: url, strategy: :list, link_resolver:,
                                                                     minimum_selector_frequency:, use_top_selectors:)
                                 engine.select_eligible(segments, limit: TOP_K)
                               else
                                 []
                               end
        end

        def materialize(ranked)
          ranked.filter_map do |entry|
            ::Html2rss::Html::SstArticleExtractor.call(entry, base_url: url, scraper: self.class,
                                                              link_resolver:)
          end
        end

        def engine
          @engine ||= Scoring::Engine.new(link_resolver:)
        end

        def minimum_selector_frequency = @opts[:minimum_selector_frequency] || DEFAULT_MINIMUM_SELECTOR_FREQUENCY
        def use_top_selectors = @opts[:use_top_selectors] || DEFAULT_USE_TOP_SELECTORS
      end
    end
  end
end
