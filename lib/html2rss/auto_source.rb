# frozen_string_literal: true

require 'dry-validation'
require 'json'
require 'nokogiri'

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
  # {include:file:lib/html2rss/auto_source/README.md}
  class AutoSource # rubocop:disable Metrics/ClassLength -- defaults + tiered extract stay on the contributor entry type
    # Default max articles to keep (also the short-circuit floor across scraper tiers).
    DEFAULT_LIMIT = 25

    # Operational scraper failures quarantined within a tier; programmer errors propagate.
    OPERATIONAL_ERRORS = [
      Html2rss::Error,
      ArgumentError,
      ::JSON::ParserError,
      ::Nokogiri::SyntaxError
    ].freeze

    # Default auto-source configuration shipped for scraper and cleanup behavior.
    DEFAULT_CONFIG = {
      limit: DEFAULT_LIMIT,
      entry_resolution: {
        enabled: true,
        max_probes: 5
      }.freeze,
      scraper: {
        native_feed: {
          enabled: true
        },
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
        json_document: {
          enabled: true
        },
        xhr_articles: {
          enabled: true
        },
        meta_oembed: {
          enabled: true
        },
        semantic_html: {
          enabled: true
        },
        html: {
          enabled: true,
          minimum_selector_frequency: Scraper::Html::DEFAULT_MINIMUM_SELECTOR_FREQUENCY,
          use_top_selectors: Scraper::Html::DEFAULT_USE_TOP_SELECTORS
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
            scraper.request_slots(opts)
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
      @json_response = response.json_response?
      @captured_responses = response.captured_responses
      @opts = opts
      @request_session = request_session
    end

    ##
    # Extracts articles by running scraper tiers until a sufficient set is found.
    #
    # Tiers: in-page structured → follow-up IO → SemanticHtml → Html.
    # SST is built at most once, lazily, by the first consumer: a heuristic tier or the
    # {Corroboration} page check of structured-tier items. Later tiers are skipped once
    # +limit+ counting articles with url+title remain after Cleanup ({#counting}); the result
    # is capped to +limit+, counting articles first. A native feed's items come first, and
    # Cleanup merges a page copy of the same article into them.
    # Html is skipped when earlier tiers already admitted at least one clean article
    # below +limit+ — quality over padding with weaker heuristic junk.
    #
    # @return [Array<Html2rss::Article>] extracted articles
    def articles
      @articles ||= extract_articles
    rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
      Log.warn({
        event_name: 'auto_source.no_scraper',
        host: url.host,
        category: error.category,
        message: "#{self.class}: no scraper matched #{url} (#{error.message})"
      }.to_json)
      @admission_drops = {}.freeze
      []
    end

    ##
    # Reason → count tallies from the final {Cleanup} pass (empty until {#articles} runs).
    #
    # @return [Hash{String => Integer}]
    def admission_drops
      @admission_drops || {}
    end

    private

    attr_reader :url, :parsed_body, :body, :request_session, :captured_responses

    # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def extract_articles
      return extract_json_document_articles if json_response?

      articles = []
      matched = false
      scraper_opts = @opts.fetch(:scraper, {})

      Scraper::SCRAPER_TIERS.each do |tier|
        break if enough_articles?(articles)
        break if skip_html_padding?(tier, articles)

        tier.each do |scraper_class|
          instance = Scraper.build_instance(
            scraper_class,
            parsed_body,
            opts: scraper_opts,
            url:,
            request_session:,
            body:,
            document: (page_document if Scraper.heuristic_tier?(tier)),
            link_resolver:,
            captured_responses:
          )
          next unless instance
          next unless instance.extractable?

          matched = true
          articles.concat(run_scraper(instance))
        end
      end

      raise Scraper.no_scraper_found_for(parsed_body, body:) unless matched

      finish_articles(articles)
    end

    def json_response?
      @json_response
    end

    def extract_json_document_articles
      instance = json_document_instance
      raise Scraper::NoScraperFound.new(category: :unsupported_surface) unless instance&.extractable?

      articles = run_scraper(instance)
      raise Scraper::NoScraperFound.new(category: :unsupported_surface) if articles.empty?

      finish_articles(articles)
    end

    def json_document_instance
      Scraper.build_instance(
        Scraper::JsonDocument,
        parsed_body,
        opts: @opts.fetch(:scraper, {}),
        url:,
        request_session:,
        body:,
        captured_responses:
      )
    end

    def finish_articles(articles)
      captured_count = articles.size
      result = cleanup_result(articles)
      @admission_drops = result.drop_tallies
      log_admission_emptied(captured_count, result) if captured_count.positive? && result.articles.empty?
      counting = counting(result.articles)
      (counting + (result.articles - counting)).first(article_limit)
    end

    def log_admission_emptied(captured_count, result)
      payload = {
        event_name: 'auto_source.admission_emptied',
        host: url.host,
        captured_count:,
        drop_tallies: result.drop_tallies
      }
      hint = Cleanup.admission_hint(result.drop_tallies)
      payload[:hint] = hint if hint
      Log.warn(payload.to_json)
    end

    def enough_articles?(articles)
      return false if articles.size < article_limit

      counting(admitted_articles(articles)).size >= article_limit
    end

    # The articles that count toward +limit+, in order: those the page shows in its content
    # ({Corroboration#shown?}), media items (audio, video) only on a media page
    # ({Corroboration#media_page?}). The others stay admitted after the counting ones.
    def counting(articles)
      media_page = corroboration.media_page?(articles)
      articles.select { (media_page || !_1.media?) && corroboration.shown?(_1) }
    end

    # Prefer fewer clean items over refilling +limit+ from the Html heuristic tier.
    def skip_html_padding?(tier, articles)
      html_only_tier?(tier) && admitted_articles(articles).any?
    end

    def html_only_tier?(tier)
      tier == [Scraper::Html]
    end

    # Cleanup is deterministic and +articles+ only grows, so one result per size is reused
    # by the tier checks and by {#finish_articles}.
    def cleanup_result(articles)
      return @cleanup_memo.last if @cleanup_memo&.first == articles.size

      Cleanup.call(articles.dup, url:, corroboration:, page_links: -> { page_links }, **cleanup_options)
             .tap { @cleanup_memo = [articles.size, _1] }
    end

    # Page SST shared by the heuristic tiers and the page check; nil for a JSON response
    # or a page without SST nodes.
    def page_document
      return @page_document if defined?(@page_document)

      @page_document = (SST::Normalizer.call(parsed_body) unless json_response?)
    end

    def link_resolver
      @link_resolver ||= Scoring::LinkResolver.new(url)
    end

    def corroboration
      @corroboration ||= Corroboration.new { page_links }
    end

    # Rendered links of the page, built once for the page check and sponsorship.
    def page_links
      @page_links ||= PageLinks.build(page_document, link_resolver:)
    end

    def admitted_articles(articles)
      cleanup_result(articles).articles.select do |article|
        article.url && !article.title.to_s.empty?
      end
    end

    def article_limit
      @opts.fetch(:limit, DEFAULT_LIMIT)
    end

    def run_scraper(instance)
      instance.map { |item| article_from_scraper_item(item, instance) }
    rescue *OPERATIONAL_ERRORS => error
      Log.warn({
        event_name: 'auto_source.quarantined',
        host: url.host,
        error_class: error.class.name,
        message: "#{self.class}: #{instance.class} quarantined #{error.class}: #{error.message}"
      }.to_json)
      []
    end

    def article_from_scraper_item(item, instance)
      case item
      when Article
        item
      when Hash
        # Hash items carry publisher-declared or structured titles: verbatim (collapse only), except an item
        # with an explicit +kicker+, which composes +Kicker: Headline+. Heuristic scrapers yield Articles
        # composed by Html::SstArticleExtractor.
        Article.new(**item, compose_title: item.key?(:kicker), scraper: instance.class)
      else
        raise TypeError, "#{instance.class} yielded #{item.class}; expected Article or Hash"
      end
    end

    def cleanup_options
      @opts.fetch(:cleanup, {})
    end
  end
end
