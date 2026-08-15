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
      # Root markers indicating likely app-shell/client-rendered surfaces.
      APP_SHELL_ROOT_SELECTORS = '#app, #root, #__next, [data-reactroot], [ng-app], [id*="app-shell"]'
      # Maximum anchors tolerated before app-shell detection is considered unlikely.
      APP_SHELL_MAX_ANCHORS = 2
      # Maximum visible text length tolerated for app-shell classification.
      APP_SHELL_MAX_VISIBLE_TEXT_LENGTH = 220

      # Extraction tiers: merge within a tier, then stop when AutoSource has enough articles.
      # Heuristic scrapers are separate tiers so SemanticHtml can satisfy before Html runs.
      SCRAPER_TIERS = [
        [Schema, Microdata, Microformats2, JsonState].freeze,
        [WordpressApi, Sitemap, MetaOembed].freeze,
        [SemanticHtml].freeze,
        [Html].freeze
      ].freeze

      # Flat ordered list (request slot accounting, detection helpers).
      SCRAPERS = SCRAPER_TIERS.flatten.freeze

      # Heuristic scrapers that share one memoized SST::Document per page.
      HEURISTIC_SCRAPERS = [SemanticHtml, Html].freeze
      # Scrapers that accept a shared follow-up +request_session+.
      REQUEST_SESSION_SCRAPERS = [WordpressApi, Sitemap, MetaOembed].freeze

      ##
      # Error raised when no suitable scraper is found.
      class NoScraperFound < Html2rss::Error
        # User-facing messages grouped by no-scraper surface category.
        CATEGORY_MESSAGES = {
          blocked_surface: 'No scrapers found: blocked surface likely (anti-bot or interstitial). ' \
                           'Target a direct listing URL, configure BOTASAURUS_SCRAPER_URL, ' \
                           'or run from an environment that can complete anti-bot checks.',
          app_shell: 'No scrapers found: app-shell surface detected (client-rendered page with little or no ' \
                     'server-rendered article HTML). Configure BOTASAURUS_SCRAPER_URL or target a direct ' \
                     'listing/update URL instead of a homepage or shell entrypoint.',
          unsupported_surface: 'No scrapers found: unsupported extraction surface for auto mode. ' \
                               'Try a direct listing/changelog/category URL, ' \
                               'or use explicit selectors in a feed config.'
        }.freeze

        # @param message [String, nil] custom error message override
        # @param category [Symbol] no-scraper classification
        def initialize(message = nil, category: :unsupported_surface)
          validate_category!(category)
          @category = category
          super(message || CATEGORY_MESSAGES.fetch(@category))
        end

        attr_reader :category

        private

        def validate_category!(category)
          return if CATEGORY_MESSAGES.key?(category)

          valid_categories = CATEGORY_MESSAGES.keys.join(', ')
          raise ArgumentError, "Unknown category: #{category.inspect}. Valid categories are: #{valid_categories}"
        end
      end

      ##
      # Returns an array of scraper classes that claim to find articles in the parsed body.
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
      # @param opts [Hash] The options hash.
      # @option opts [Hash] :wordpress_api scraper toggle and configuration
      # @option opts [Hash] :schema scraper toggle and configuration
      # @option opts [Hash] :microdata scraper toggle and configuration
      # @option opts [Hash] :microformats2 scraper toggle and configuration
      # @option opts [Hash] :json_state scraper toggle and configuration
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
        tier.intersect?(HEURISTIC_SCRAPERS)
      end

      ##
      # @param parsed_body [Nokogiri::HTML::Document]
      # @return [SST::Document, nil]
      def self.normalize_sst(parsed_body)
        SST::Normalizer.call(parsed_body)
      rescue ArgumentError
        nil
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
      # @option opts [Hash] :wordpress_api scraper toggle and configuration
      # @option opts [Hash] :schema scraper toggle and configuration
      # @option opts [Hash] :microdata scraper toggle and configuration
      # @option opts [Hash] :microformats2 scraper toggle and configuration
      # @option opts [Hash] :json_state scraper toggle and configuration
      # @option opts [Hash] :meta_oembed scraper toggle and configuration
      # @option opts [Hash] :semantic_html scraper toggle and configuration
      # @option opts [Hash] :html scraper toggle and configuration
      # @option opts [Hash] :sitemap scraper toggle and configuration
      # @return [Object, nil]
      # rubocop:disable Metrics/ParameterLists -- construction context for structured and heuristic scrapers
      def self.build_instance(scraper, parsed_body, opts:, url:, request_session: nil, body: nil, document: nil,
                              link_resolver: nil)
        return unless opts.dig(scraper.options_key, :enabled)
        return if HEURISTIC_SCRAPERS.include?(scraper) && document.nil?

        scraper_opts = opts.fetch(scraper.options_key, {}).except(:enabled)
        kwargs = construction_kwargs(scraper, request_session:, body:, document:, link_resolver:)
        scraper.new(parsed_body, url:, **kwargs, **scraper_opts)
      end
      # rubocop:enable Metrics/ParameterLists

      ##
      # @param instance [Object]
      # @param parsed_body [Nokogiri::HTML::Document]
      # @return [Boolean]
      def self.extractable_instance?(instance, parsed_body)
        return instance.extractable? if instance.respond_to?(:extractable?)

        instance.class.articles?(parsed_body)
      end

      ##
      # @param parsed_body [Nokogiri::HTML::Document]
      # @param body [String, nil] raw response body (preferred for blocked-surface checks)
      # @return [NoScraperFound]
      def self.no_scraper_found_for(parsed_body, body: nil)
        NoScraperFound.new(category: classify_no_scraper_surface(parsed_body, body:))
      end

      def self.construction_kwargs(scraper, request_session:, body:, document:, link_resolver:)
        if HEURISTIC_SCRAPERS.include?(scraper)
          { document:, link_resolver: }.compact
        else
          {}.tap do |kwargs|
            kwargs[:request_session] = request_session if REQUEST_SESSION_SCRAPERS.include?(scraper)
            kwargs[:body] = body if scraper == Sitemap
          end
        end
      end
      private_class_method :construction_kwargs

      def self.classify_no_scraper_surface(parsed_body, body: nil)
        return :blocked_surface if blocked_surface?(parsed_body, body:)
        return :app_shell if app_shell_surface?(parsed_body)

        :unsupported_surface
      end
      private_class_method :classify_no_scraper_surface

      def self.blocked_surface?(parsed_body, body: nil)
        Html2rss::RequestService::BlockedSurface.interstitial?(body || parsed_body.to_html)
      end
      private_class_method :blocked_surface?

      def self.app_shell_surface?(parsed_body)
        root_marker = parsed_body.at_css(APP_SHELL_ROOT_SELECTORS)
        return false unless root_marker

        sparse_anchor_surface?(parsed_body) &&
          no_article_markers?(parsed_body) &&
          short_visible_text?(parsed_body)
      end
      private_class_method :app_shell_surface?

      def self.sparse_anchor_surface?(parsed_body)
        parsed_body.css('body a[href]').size <= APP_SHELL_MAX_ANCHORS
      end
      private_class_method :sparse_anchor_surface?

      def self.no_article_markers?(parsed_body)
        parsed_body.css(
          'article, main article, [itemtype*="Article"], [itemprop="articleBody"]'
        ).empty?
      end
      private_class_method :no_article_markers?

      def self.short_visible_text?(parsed_body)
        visible_text_length(parsed_body) <= APP_SHELL_MAX_VISIBLE_TEXT_LENGTH
      end
      private_class_method :short_visible_text?

      def self.visible_text_length(parsed_body)
        body = parsed_body.at_css('body')
        return 0 unless body

        text_nodes = body.xpath('.//text()[not(ancestor::script or ancestor::style or ancestor::noscript)]')
        text_nodes.map(&:text).join(' ').gsub(/\s+/, ' ').strip.length
      end
      private_class_method :visible_text_length
    end
  end
end
