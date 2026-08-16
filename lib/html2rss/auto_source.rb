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
  # rubocop:disable Metrics/ClassLength -- defaults + tiered extract stay on the contributor entry type
  class AutoSource
    # Default max articles to keep (also the short-circuit floor across scraper tiers).
    DEFAULT_LIMIT = 25

    # Default auto-source configuration shipped for scraper and cleanup behavior.
    DEFAULT_CONFIG = {
      limit: DEFAULT_LIMIT,
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
        xhr_articles: {
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
    # @option opts [Integer] :limit max articles to keep; later tiers stop once this many survive Cleanup
    # @option opts [Hash] :scraper scraper configuration map
    # @option opts [Hash] :cleanup cleanup configuration map
    # @return [void]
    def initialize(response, opts = DEFAULT_CONFIG, request_session: nil)
      @parsed_body = response.parsed_body
      @body = response.body
      @url = response.url
      @captured_responses = response.captured_responses
      @opts = opts
      @request_session = request_session
    end

    ##
    # Extracts articles by running scraper tiers until a sufficient set is found.
    #
    # Tiers: in-page structured → follow-up IO → SemanticHtml → Html.
    # SST is built only when a heuristic tier runs. Later tiers are skipped once
    # +limit+ articles with url+title remain after Cleanup; the result is capped to +limit+.
    # Html is skipped when earlier tiers already admitted at least one clean article
    # below +limit+ — quality over padding with weaker heuristic junk.
    #
    # @return [Array<Html2rss::Article>] extracted articles
    def articles
      @articles ||= extract_articles
    rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
      Log.warn "#{self.class}: no scraper matched #{url} (#{error.message})"
      []
    end

    private

    attr_reader :url, :parsed_body, :body, :request_session, :captured_responses

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def extract_articles
      articles = []
      matched = false
      document = nil
      link_resolver = nil
      scraper_opts = @opts.fetch(:scraper, {})

      Scraper::SCRAPER_TIERS.each do |tier|
        break if enough_articles?(articles)
        break if skip_html_padding?(tier, articles)

        if Scraper.heuristic_tier?(tier)
          document ||= Scraper.normalize_sst(parsed_body)
          next unless document

          link_resolver ||= ::Html2rss::Scoring::LinkResolver.new(url)
        end

        tier.each do |scraper_class|
          instance = Scraper.build_instance(
            scraper_class,
            parsed_body,
            opts: scraper_opts,
            url:,
            request_session:,
            body:,
            document:,
            link_resolver:,
            captured_responses:
          )
          next unless instance
          next unless Scraper.extractable_instance?(instance, parsed_body)

          matched = true
          articles.concat(run_scraper(instance))
        end
      end

      raise Scraper.no_scraper_found_for(parsed_body, body:) unless matched

      Cleanup.call(articles, url:, **cleanup_options).first(article_limit)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def enough_articles?(articles)
      return false if articles.size < article_limit

      admitted_articles(articles).size >= article_limit
    end

    # Prefer fewer clean items over refilling +limit+ from the Html heuristic tier.
    def skip_html_padding?(tier, articles)
      html_only_tier?(tier) && admitted_articles(articles).any?
    end

    def html_only_tier?(tier)
      tier == [Scraper::Html]
    end

    def admitted_articles(articles)
      Cleanup.call(articles.dup, url:, **cleanup_options).select do |article|
        article.url && !article.title.to_s.empty?
      end
    end

    def article_limit
      @opts.fetch(:limit, DEFAULT_LIMIT)
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
  # rubocop:enable Metrics/ClassLength
end
