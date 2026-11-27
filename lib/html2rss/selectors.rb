# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  ##
  # This scraper is designed to scrape articles from a given HTML page using CSS
  # selectors defined in the feed config.
  #
  # It supports the traditional feed configs that html2rss originally provided,
  # ensuring compatibility with existing setups.
  #
  # Additionally, it uniquely offers the capability to convert JSON into XML,
  # extending its versatility for diverse data processing workflows.
  #
  # {include:file:lib/html2rss/selectors/README.md}
  class Selectors
    # Raised when a selector key is missing or not allowed for extraction.
    class InvalidSelectorName < Html2rss::Error; end

    include Enumerable

    # Wire spelling of the default items selector.
    # Runtime CSS is {Html::Navigator::MAIN_ANCHOR_SELECTOR}.
    DEFAULT_ITEMS_SELECTOR = 'a[href]'
    # Default selectors options merged into user configuration.
    DEFAULT_CONFIG = { items: { selector: DEFAULT_ITEMS_SELECTOR, enhance: true } }.freeze

    # Selector key that points to the root list of article nodes.
    ITEMS_SELECTOR_KEY = :items
    # Supported RSS item attributes extractable through selectors.
    ITEM_TAGS = %i[title url description author comments published_at guid enclosure categories].freeze
    # Admission-drop reason tallied for selector items that carry no URL (same shape as
    # {AutoSource#admission_drops}).
    MISSING_URL_REASON = 'missing_url'

    # Item keys that enhance can fill. Skip the extractor when all are already present.
    ENHANCEABLE_KEYS = %i[title url description published_at enclosures categories].freeze

    ##
    # Initializes a new Selectors instance.
    #
    # @param response [RequestService::Response] The response object.
    # @param selectors [Hash] A hash of CSS selectors.
    # @param time_zone [String] Time zone string used for date parsing.
    # @param vocabulary [Vocabulary::Scope] the page language's scope, resolved by the caller
    def initialize(response, selectors:, time_zone:, vocabulary:)
      @response = response
      @vocabulary = vocabulary
      @url = response.base_url
      @selectors = selectors
      @time_zone = time_zone
      @parsed_body = @selected_items = @item_enhancer = nil
      @unlinked_count = 0
      @item_fields = ItemFields.new(selectors, items_key: ITEMS_SELECTOR_KEY)
    end

    ##
    # Returns articles extracted from the response.
    # Reverses order if config specifies reverse ordering.
    #
    # @return [Array<Html2rss::Article>]
    def articles
      @articles ||= @selectors.dig(ITEMS_SELECTOR_KEY, :order) == 'reverse' ? to_a.tap(&:reverse!) : to_a
    end

    ##
    # Drop tallies for the last iteration: items skipped for having no URL, as {AutoSource#admission_drops}.
    #
    # @return [Hash{String => Integer}] empty when every item was linked
    def admission_drops
      @unlinked_count.positive? ? { MISSING_URL_REASON => @unlinked_count }.freeze : {}.freeze
    end

    ##
    # Iterates over each scraped article. An item without a URL is skipped and tallied in {#admission_drops},
    # as in auto-source ({Html2rss::Article#linked?}).
    #
    # @yield [article] Gives each article as an Html2rss::Article.
    # @return [Enumerator] An enumerator if no block is given.
    def each(&)
      return enum_for unless block_given?

      @unlinked_count = 0
      seen = Set.new
      selected_items.each do |item|
        article_hash = extract_article(item)
        enhance_article_hash(article_hash, item) if enhance?
        article = build_article(article_hash)
        article.linked? ? (yield article if admitted?(article, seen)) : @unlinked_count += 1
      end
    end

    ##
    # Yields +baseline+, +enhanced+, and the item node per list entry for enhance diagnostics.
    #
    # @param linked_only [Boolean] skip items {#each} would drop for having no URL
    # Consumed by {Curation::Test::EnhanceAudit} so the extraction loop has one owner.
    #
    # @yieldparam baseline [Hash]
    # @yieldparam enhanced [Hash]
    # @yieldparam item [Nokogiri::XML::Element]
    # @return [Enumerator] if no block is given
    def each_enhance_pair(linked_only: false)
      return enum_for(:each_enhance_pair, linked_only:) unless block_given?

      seen = Set.new
      selected_items.each do |item|
        baseline = extract_article(item)
        enhanced = enhance_article_hash(baseline.dup, item)
        yield baseline, enhanced, item unless linked_only && !admitted?(build_article(enhanced), seen)
      end
    end

    ##
    # Selects the value for a given attribute from an HTML element.
    #
    # @param name [Symbol, String] Name of the attribute.
    # @param item [Nokogiri::XML::Element] The HTML element to process.
    # @param base_url [String, Html2rss::Url] base URL for relative extraction values
    # @return [Object, Array<Object>] The selected value(s).
    # @raise [InvalidSelectorName] If the attribute name is invalid or not defined.
    def select(name, item, base_url: @url)
      select_in_scope(name, item_env_for(item, base_url))
    end

    ##
    # Selects the value for a given attribute within an existing {ItemEnv}.
    # Used by {ItemEnv#select} so nested selects reuse one env per extraction pass.
    #
    # @param name [Symbol, String] Name of the attribute.
    # @param scope [ItemEnv] Per-item extraction scope.
    # @return [Object, Array<Object>] The selected value(s).
    # @raise [InvalidSelectorName] If the attribute name is invalid or not defined.
    def select_in_scope(name, scope)
      name = name.to_sym
      raise InvalidSelectorName, "Attribute selector '#{name}' is reserved for items." if name == ITEMS_SELECTOR_KEY

      @item_fields.select(name, scope)
    end

    private

    attr_reader :response

    def items_selector
      selector = @selectors.dig(ITEMS_SELECTOR_KEY, :selector)
      default_items_selector?(selector) ? Html::Navigator::MAIN_ANCHOR_SELECTOR : selector
    end

    def default_items_selector?(selector)
      text = selector.to_s.strip
      text.empty? || text == DEFAULT_ITEMS_SELECTOR
    end

    ##
    # Whether +selectors.items.enhance+ is on: each matched item node fills fields that explicit
    # selectors left empty (see {ENHANCEABLE_KEYS}) via {ItemEnhancer}, using only the
    # item's own markup and making no extra requests.
    #
    # @return [Boolean]
    def enhance? = !!@selectors.dig(ITEMS_SELECTOR_KEY, :enhance)

    def selected_items
      @selected_items ||= parsed_body.css(items_selector)
    end

    def parsed_body
      @parsed_body ||= build_parsed_body(response)
    end

    def build_parsed_body(page_response)
      if page_response.json_response?
        fragment = JsonXml.call(page_response.parsed_body)
        Nokogiri::HTML5.fragment(fragment)
      else
        page_response.parsed_body
      end
    end

    def build_article(article_hash) = Article.new(**article_hash, scraper: self.class)

    def extract_article(item) = @item_fields.article_hash(item_env_for(item, @url))

    # The one admission rule of {#each} and {#each_enhance_pair}: a linked article, and with enhance on the
    # first one carrying its URL.
    def admitted?(article, seen) = article.linked? && (!enhance? || seen.add?(article.url.to_s))

    def enhance_article_hash(article_hash, article_tag)
      return article_hash if enhanceable_fields_present?(article_hash)

      extracted = item_enhancer.fields_for(article_tag, url: !@selectors.key?(:url))
      return article_hash unless extracted

      extracted.each_with_object(article_hash) do |(key, value), hash|
        next if value.nil? || (hash.key?(key) && hash[key])

        hash[key] = value
      end
    end

    def item_enhancer
      @item_enhancer ||= ItemEnhancer.new(selected_items, base_url: @url, time_zone: @time_zone,
                                                          vocabulary: @vocabulary)
    end

    def enhanceable_fields_present?(article_hash)
      ENHANCEABLE_KEYS.all? { |key| article_hash[key] }
    end

    def item_env_for(item, base_url)
      ItemEnv.new(item:, base_url:, scraper: self, time_zone: @time_zone)
    end
  end
end
