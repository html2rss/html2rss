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
    DEFAULT_LIMIT = 50

    # Raised when a scraper yields an item that is neither an Article nor a Hash (a scraper bug).
    class ScraperContractError < Html2rss::ContractError; end

    # Operational scraper failures quarantined within a tier; programmer errors (including any
    # {Html2rss::ContractError}) propagate.
    # +ArgumentError+ stays for stdlib raises on publisher bytes (e.g. +invalid byte sequence+ after
    # +CGI.unescapeHTML+ of a surrogate entity); lib raises are {Html2rss::Error} (CONTEXT.md § Error handling).
    OPERATIONAL_ERRORS = [
      Html2rss::Error,
      ArgumentError,
      ::JSON::ParserError,
      ::Nokogiri::SyntaxError
    ].freeze

    # Default auto-source configuration shipped for scraper and cleanup behavior.
    DEFAULT_CONFIG = {
      limit: DEFAULT_LIMIT,
      entry_resolution: EntryResolution::DEFAULT_CONFIG,
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
    # @param vocabulary [Html2rss::Vocabulary::Scope] the page language's scope, resolved by the caller once and
    #   shared by every classifier of this run
    # @param time_zone [String, nil] channel time zone for naive leftover dates (nil reads as UTC)
    # @option opts [Integer] :limit max articles to keep; later tiers stop once this many survive Cleanup
    # @option opts [Hash] :scraper scraper configuration map
    # @option opts [Hash] :cleanup cleanup configuration map
    # @return [void]
    def initialize(response, opts = DEFAULT_CONFIG, vocabulary:, request_session: nil, time_zone: nil)
      @vocabulary = vocabulary
      @time_zone = time_zone
      @parsed_body = response.parsed_body
      @body = response.body
      @url = response.url
      @json_response = response.json_response?
      @captured_responses = response.captured_responses
      @opts = opts
      @request_session = request_session
      @cards_read = false
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
      Log.event(
        :warn, 'auto_source.no_scraper',
        host: url.host,
        category: error.category,
        message: "#{self.class}: no scraper matched #{url} (#{error.message})"
      )
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

    ##
    # What the native feed this page advertises states about its channel ({Scraper::NativeFeed#channel}):
    # nil until {#articles} runs, or when no feed was read.
    #
    # @return [Html2rss::Syndication::ChannelFacts, nil]
    def feed_channel = @native_feed&.channel

    private

    attr_reader :url, :parsed_body, :body, :request_session, :captured_responses, :vocabulary

    def extract_articles
      return extract_json_document_articles if json_response?

      articles = []
      matched = false
      Scraper::SCRAPER_TIERS.each do |tier|
        break if enough_articles?(articles) || skip_html_padding?(tier, articles)

        matched |= run_tier(tier, articles).any?
      end
      raise Scraper.no_scraper_found_for(parsed_body, body:) unless matched

      finish_articles(articles)
    end

    # Runs every enabled, extractable scraper of +tier+, appending its articles.
    #
    # @return [Array<Object>] the scrapers that matched
    def run_tier(tier, articles)
      heuristic = Scraper.heuristic_tier?(tier)
      @cards_read = true if heuristic
      context = scraper_context(document: (page_document if heuristic), link_resolver:, time_zone: @time_zone)
      tier.filter_map { run_instance(_1, context, articles) }
    end

    def run_instance(scraper_class, context, articles)
      instance = Scraper.build_instance(scraper_class, context)
      return unless instance&.extractable?

      articles.concat(run_scraper(instance))
      @native_feed = instance if instance.is_a?(Scraper::NativeFeed)
      instance
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
      Scraper.build_instance(Scraper::JsonDocument, scraper_context)
    end

    def scraper_context(**page_state)
      Scraper::Context.new(parsed_body:, opts: @opts.fetch(:scraper, {}), url:, request_session:, body:,
                           captured_responses:, **page_state)
    end

    def finish_articles(articles)
      captured_count = articles.size
      result = cleanup_result(articles)
      @admission_drops = result.drop_tallies
      log_admission_emptied(captured_count, result) if captured_count.positive? && result.articles.empty?
      counting = counting(result.articles)
      (counting + padding(result.articles, counting)).first(article_limit)
    end

    def log_admission_emptied(captured_count, result)
      hint = Cleanup.admission_hint(result.drop_tallies)
      fields = { host: url.host, captured_count:, drop_tallies: result.drop_tallies, hint: }.compact
      Log.event(:warn, 'auto_source.admission_emptied', **fields)
    end

    def enough_articles?(articles)
      return false if articles.size < article_limit

      counting(admitted_articles(articles)).size >= article_limit
    end

    # The articles that count toward +limit+, in order: those the page shows in its content
    # ({Corroboration#shown?}), media items (audio, video) only on a media page
    # ({Corroboration#media_page?}), where only media items count (the other cards link to other
    # shows and never pad). Elsewhere the others stay admitted after the counting ones. A page is
    # judged a media page only once a heuristic tier has read its cards: structured items alone
    # cannot tell a podcast page from a news page with an audio list. A media page's counting
    # items are in page order ({Corroboration#page_order}), not tier order.
    def counting(articles)
      media_page = media_page?(articles)
      counted = articles.select { (media_page ? _1.media? : !_1.media?) && corroboration.shown?(_1) }
      media_page ? corroboration.page_order(counted) : counted
    end

    def media_page?(articles)
      @cards_read && corroboration.media_page?(articles)
    end

    # The admitted items that fill a feed the counting ones leave short. A media page is its
    # episodes: the other cards on it link to other shows, so they never pad.
    def padding(articles, counting)
      media_page?(articles) ? [] : articles - counting
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

      Cleanup.call(articles.dup, **page_inputs, feed_url: @native_feed&.feed_url, **cleanup_options)
             .tap { @cleanup_memo = [articles.size, _1] }
    end

    # What {Cleanup} reads of the page: its language and URL, and the page-scoped label reader, route-facts memo
    # and page check, so each text and URL is read once per run.
    def page_inputs
      { url:, vocabulary:, classifier: link_resolver.text_classifier, facts: facts_lookup,
        corroboration:, page_links: -> { page_links } }
    end

    # Page SST shared by the heuristic tiers and the page check; nil for a JSON response
    # or a page without SST nodes.
    def page_document
      return @page_document if defined?(@page_document)

      @page_document = (SST::Normalizer.call(parsed_body, vocabulary:) unless json_response?)
    end

    # The page's route-facts memo as a lookup, for the stages that read a URL's destination facts.
    def facts_lookup = ->(url) { link_resolver.facts_for(url) }

    def link_resolver
      @link_resolver ||= Scoring::LinkResolver.new(url, vocabulary:)
    end

    def corroboration
      @corroboration ||= Corroboration.new(vocabulary, facts: facts_lookup) { page_links }
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
    rescue ContractError
      raise
    rescue *OPERATIONAL_ERRORS => error
      Log.event(
        :warn, 'auto_source.quarantined',
        host: url.host, error_class: error.class.name,
        message: "#{self.class}: #{instance.class} quarantined #{error.class}: #{error.message}"
      )
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
        Article.new(**localized_date(composed_title(item)), scraper: instance.class)
      else
        raise ScraperContractError, "#{instance.class} yielded #{item.class}; expected Article or Hash"
      end
    end

    # Hash scrapers emit published_at strings; a naive one is read in the channel time zone.
    def localized_date(item)
      string = item[:published_at].to_s
      parsed = Html::ArticleRules::Date.parse_datetime(string, time_zone: @time_zone)
      parsed ? item.merge(published_at: parsed) : item
    end

    def composed_title(item)
      return item unless item.key?(:kicker)

      item.except(:kicker).merge(title: Article::Title.compose(item[:title], kicker: item[:kicker], vocabulary:))
    end

    def cleanup_options
      @opts.fetch(:cleanup, {})
    end
  end
end
