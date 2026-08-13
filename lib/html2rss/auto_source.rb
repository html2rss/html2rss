# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  ##
  # The AutoSource class automatically extracts articles from a given URL by
  # utilizing a collection of Scrapers. These scrapers analyze and
  # parse popular structured data formats—such as schema, microdata, and
  # open graph—to identify and compile article elements into unified articles.
  #
  # Scrapers supporting plain HTML are also available for sites without structured data,
  # though results may vary based on page markup.
  #
  # @see Html2rss::AutoSource::Scraper::Schema
  # @see Html2rss::AutoSource::Scraper::SemanticHtml
  # @see Html2rss::AutoSource::Scraper::Html
  class AutoSource
    # Default auto-source configuration shipped for scraper and cleanup behavior.
    DEFAULT_CONFIG = {
      scraper: {
        wordpress_api: {
          enabled: true
        },
        sitemap: {
          enabled: true,
          min_priority: Scraper::Sitemap::Parser::DEFAULT_MIN_PRIORITY,
          max_age_days: Scraper::Sitemap::Parser::DEFAULT_MAX_AGE_DAYS
        },
        schema: {
          enabled: true
        },
        microdata: {
          enabled: true
        },
        microformats2: {
          enabled: true
        },
        json_state: {
          enabled: true
        },
        meta_oembed: {
          enabled: true
        },
        semantic_html: {
          enabled: true,
          fallback_anchorless: true
        },
        html: {
          enabled: true,
          minimum_selector_frequency: Scraper::Html::DEFAULT_MINIMUM_SELECTOR_FREQUENCY,
          use_top_selectors: Scraper::Html::DEFAULT_USE_TOP_SELECTORS,
          fallback_anchorless: true
        }
      },
      cleanup: Cleanup::DEFAULT_CONFIG
    }.freeze

    class << self
      ##
      # Returns the sum of required request slots for all enabled scrapers in the config.
      #
      # @param config [Hash, nil] auto_source configuration hash
      # @return [Integer] total request slots required by scrapers
      def request_slots_for(config)
        return 0 unless config

        Scraper::SCRAPERS.sum do |scraper|
          if config.dig(:scraper, scraper.options_key, :enabled)
            opts = config.dig(:scraper, scraper.options_key)
            scraper.respond_to?(:request_slots) ? scraper.request_slots(opts) : 0
          else
            0
          end
        end
      end
    end

    ##
    # @param response [Html2rss::RequestService::Response] initial page response
    # @param opts [Hash] validated auto-source options
    # @param request_session [Html2rss::RequestSession, nil] shared request session for follow-up fetches
    # @option opts [Hash] :scraper scraper configuration map
    # @option opts [Hash] :cleanup cleanup configuration map
    # @return [void]
    def initialize(response, opts = DEFAULT_CONFIG, request_session: nil)
      @parsed_body = response.parsed_body
      @body = response.body
      @url = response.url
      @opts = opts
      @request_session = request_session
    end

    ##
    # Extracts article candidates by selecting every scraper that can explain the
    # page shape, running those scrapers, and normalizing the resulting hashes
    # into `Article` objects.
    #
    # The contributor-facing flow is:
    # 1. choose scraper instances that match the page
    # 2. let each scraper collect its own candidates
    # 3. clean and deduplicate the merged article list
    #
    # Scrapers with expensive precomputation, such as `SemanticHtml`, keep that
    # state on the instance so detection and extraction can reuse the same work.
    #
    # @return [Array<Html2rss::Article>] extracted articles
    def articles
      @articles ||= extract_articles
    rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
      Log.warn "#{self.class}: no scraper matched #{url} (#{error.message})"
      []
    end

    private

    attr_reader :url, :parsed_body, :body, :request_session

    def extract_articles
      scraper_instances = Scraper.instances_for(
        parsed_body, url:, request_session:, body:, opts: @opts[:scraper]
      )
      return [] if scraper_instances.empty?

      # Scrapers are run sequentially.
      articles = scraper_instances.flat_map do |instance|
        run_scraper(instance)
      end
      Cleanup.call(articles, url:, **cleanup_options)
    end

    def run_scraper(instance)
      instance.each.map do |item|
        case item
        when Article
          item
        when Hash
          Article.new(**item, scraper: instance.class)
        else
          raise TypeError, "#{instance.class} yielded #{item.class}; expected Article or Hash"
        end
      end
    end

    def cleanup_options
      @opts.fetch(:cleanup, {})
    end
  end
end
