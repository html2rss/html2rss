# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # The Scraper module contains all scrapers that can be used to extract articles.
    # Each scraper should implement an `each` method that yields article hashes.
    # Each scraper should also implement an `articles?` method that returns true if the scraper
    # can potentially be used to extract articles from the given HTML.
    #
    # Detection is intentionally shallow for most scrapers, but instance-based
    # matching is available for scrapers that need to carry expensive selection
    # state forward into extraction.
    module Scraper
      # Extraction tiers: merge within a tier, then stop when AutoSource has enough articles.
      # Heuristic scrapers are separate tiers so SemanticHtml can satisfy before Html runs.
      # NativeFeed is tier 0 so syndication wins before structured HTML scrapers.
      SCRAPER_TIERS = [
        [NativeFeed].freeze,
        [Schema, Microdata, Microformats2, JsonState, XhrArticles].freeze,
        [WordpressApi, Sitemap, MetaOembed].freeze,
        [SemanticHtml].freeze,
        [Html].freeze
      ].freeze

      # JSON response body scrapers (routed by AutoSource before SCRAPER_TIERS).
      DOCUMENT_SCRAPERS = [JsonDocument].freeze

      # Flat ordered list (request slot accounting, detection helpers).
      SCRAPERS = (DOCUMENT_SCRAPERS + SCRAPER_TIERS.flatten).freeze

      # Heuristic scrapers that share one memoized SST::Document per page. The only titles composed
      # (+Kicker: Headline+, noise stripped): their cards are read by Html::SstArticleExtractor. Every
      # other scraper yields publisher-declared or structured headlines, kept verbatim (collapse only).
      HEURISTIC_SCRAPERS = Set[SemanticHtml, Html].freeze
      # In-page structured scrapers whose items {Corroboration} checks against the rendered page.
      # Publisher-declared sources (NativeFeed, WordpressApi, Sitemap, MetaOembed) stay exempt.
      CORROBORATED_SCRAPERS = Set[Schema, Microdata, Microformats2, JsonState, XhrArticles, JsonDocument].freeze
      # Scrapers whose items are read off the rendered page: such an item needs a title ({Cleanup}
      # drops it as +blank_title+), while a publisher-declared item (feed, API) may be untitled.
      PAGE_SCRAPERS = (CORROBORATED_SCRAPERS | HEURISTIC_SCRAPERS).freeze
      # Scrapers that accept a shared follow-up +request_session+.
      REQUEST_SESSION_SCRAPERS = Set[NativeFeed, WordpressApi, Sitemap, MetaOembed].freeze
      # Scrapers that consume browser-captured XHR/fetch JSON bodies.
      CAPTURED_RESPONSE_SCRAPERS = Set[XhrArticles].freeze

      ##
      # Error raised when no suitable scraper is found.
      class NoScraperFound < Html2rss::Error
        # @param message [String, nil] custom error message override
        # @param category [Symbol] no-scraper classification
        def initialize(message = nil, category: :unsupported_surface)
          validate_category!(category)
          @category = category
          super(message || "No scrapers found: #{Html2rss::SurfaceCategory::MESSAGES.fetch(@category)}")
        end

        attr_reader :category

        private

        def validate_category!(category)
          return if Html2rss::SurfaceCategory::MESSAGES.key?(category)

          valid_categories = Html2rss::SurfaceCategory::MESSAGES.keys.join(', ')
          raise InvalidOption, "Unknown category: #{category.inspect}. Valid categories are: #{valid_categories}"
        end
      end

      ##
      # Returns an array of scraper classes that claim to find articles in the parsed body.
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
      # @param opts [Hash] The options hash.
      # @option opts [Hash] :native_feed scraper toggle and configuration
      # @option opts [Hash] :wordpress_api scraper toggle and configuration
      # @option opts [Hash] :schema scraper toggle and configuration
      # @option opts [Hash] :microdata scraper toggle and configuration
      # @option opts [Hash] :microformats2 scraper toggle and configuration
      # @option opts [Hash] :json_state scraper toggle and configuration
      # @option opts [Hash] :json_document scraper toggle and configuration
      # @option opts [Hash] :xhr_articles scraper toggle and configuration
      # @option opts [Hash] :meta_oembed scraper toggle and configuration
      # @option opts [Hash] :semantic_html scraper toggle and configuration
      # @option opts [Hash] :html scraper toggle and configuration
      # @option opts [Hash] :sitemap scraper toggle and configuration
      # @return [Array<Class>] An array of scraper classes that can handle the parsed body.
      def self.from(parsed_body, opts = Html2rss::AutoSource::DEFAULT_CONFIG[:scraper])
        scrapers = SCRAPERS.select { |scraper| opts.dig(scraper.options_key, :enabled) }
        scrapers.select! { |scraper| scraper.articles?(parsed_body) }

        raise no_scraper_found_for(parsed_body) if scrapers.empty?

        scrapers
      end

      ##
      # @param tier [Array<Class>]
      # @return [Boolean]
      def self.heuristic_tier?(tier)
        HEURISTIC_SCRAPERS.intersect?(tier)
      end

      ##
      # Builds a scraper when enabled; returns nil when disabled.
      #
      # @param scraper [Class]
      # @param parsed_body [Nokogiri::HTML::Document]
      # @param opts [Hash] full scraper options map
      # @param url [Html2rss::Url, String]
      # @param request_session [Html2rss::RequestSession, nil]
      # @param body [String, nil]
      # @param document [SST::Document, nil]
      # @param link_resolver [Scoring::LinkResolver, nil]
      # @param time_zone [String, nil] channel time zone for naive leftover dates
      # @param captured_responses [Array<Hash>] browser-captured JSON XHR/fetch bodies
      # @option opts [Hash] :wordpress_api scraper toggle and configuration
      # @option opts [Hash] :schema scraper toggle and configuration
      # @option opts [Hash] :microdata scraper toggle and configuration
      # @option opts [Hash] :microformats2 scraper toggle and configuration
      # @option opts [Hash] :json_state scraper toggle and configuration
      # @option opts [Hash] :json_document scraper toggle and configuration
      # @option opts [Hash] :xhr_articles scraper toggle and configuration
      # @option opts [Hash] :meta_oembed scraper toggle and configuration
      # @option opts [Hash] :semantic_html scraper toggle and configuration
      # @option opts [Hash] :html scraper toggle and configuration
      # @option opts [Hash] :sitemap scraper toggle and configuration
      # @return [Object, nil]
      # rubocop:disable-next Metrics/ParameterLists, Metrics/MethodLength -- construction context for structured and heuristic scrapers
      def self.build_instance(scraper, parsed_body, opts:, url:, request_session: nil, body: nil, document: nil,
                              link_resolver: nil, time_zone: nil, captured_responses: [])
        return unless opts.dig(scraper.options_key, :enabled)
        return if HEURISTIC_SCRAPERS.include?(scraper) && document.nil?

        scraper_opts = opts.fetch(scraper.options_key, {}).except(:enabled)
        kwargs = construction_kwargs(
          scraper,
          request_session:,
          body:,
          document:,
          link_resolver:,
          time_zone:,
          captured_responses:
        )
        scraper.new(parsed_body, url:, **kwargs, **scraper_opts)
      end

      ##
      # @param parsed_body [Nokogiri::HTML::Document]
      # @param body [String, nil] raw response body (preferred for blocked-surface checks)
      # @return [NoScraperFound]
      def self.no_scraper_found_for(parsed_body, body: nil)
        NoScraperFound.new(category: Html2rss::SurfaceCategory.classify(parsed_body, body:))
      end

      def self.construction_kwargs(scraper, request_session:, body:, document:, link_resolver:, time_zone:, # rubocop:disable Metrics/ParameterLists -- scraper construction bag
                                   captured_responses:)
        if HEURISTIC_SCRAPERS.include?(scraper)
          { document:, link_resolver:, time_zone: }.compact
        else
          {}.tap do |kwargs|
            kwargs[:request_session] = request_session if REQUEST_SESSION_SCRAPERS.include?(scraper)
            kwargs[:body] = body if scraper == Sitemap
            kwargs[:captured_responses] = captured_responses if CAPTURED_RESPONSE_SCRAPERS.include?(scraper)
          end
        end
      end
      private_class_method :construction_kwargs
    end
  end
end
