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
  class Selectors
    # Raised when a selector key is missing or not allowed for extraction.
    class InvalidSelectorName < Html2rss::Error; end

    include Enumerable

    # Default selectors options merged into user configuration.
    DEFAULT_CONFIG = { items: { enhance: true } }.freeze

    # Selector key that points to the root list of article nodes.
    ITEMS_SELECTOR_KEY = :items
    # Supported RSS item attributes extractable through selectors.
    ITEM_TAGS = %i[title url description author comments published_at guid enclosure categories].freeze
    # Item attributes that require dedicated extraction logic.
    SPECIAL_ATTRIBUTES = Set[:guid, :enclosure, :categories].freeze
    # Config selector keys that map onto a different {Article} attribute.
    # +:enclosure+ stays singular in YAML; Article stores +:enclosures+.
    SELECTOR_TO_ARTICLE_KEY = { enclosure: :enclosures }.freeze
    # Selector keys that may be copied onto an Article (PROVIDED_KEYS + mapped aliases).
    SELECTABLE_SELECTOR_KEYS = Set[*(Html2rss::Article::PROVIDED_KEYS + SELECTOR_TO_ARTICLE_KEY.keys)].freeze

    ##
    # Initializes a new Selectors instance.
    #
    # @param response [RequestService::Response] The response object.
    # @param selectors [Hash] A hash of CSS selectors.
    # @param time_zone [String] Time zone string used for date parsing.
    def initialize(response, selectors:, time_zone:)
      @response = response
      @url = response.url
      @selectors = selectors
      @time_zone = time_zone
      @rss_item_attributes = @selectors.keys.select { SELECTABLE_SELECTOR_KEYS.include?(_1) }
      @attribute_selector = AttributeSelector.new
      @parsed_body = nil
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
    # Iterates over each scraped article.
    #
    # @yield [article] Gives each article as an Html2rss::Article.
    # @return [Enumerator] An enumerator if no block is given.
    def each(&)
      return enum_for(:each) unless block_given?

      enhance = enhance?

      parsed_body.css(items_selector).each do |item|
        article_hash = extract_article(item)

        enhance_article_hash(article_hash, item) if enhance

        yield Html2rss::Article.new(**article_hash, scraper: self.class)
      end
    end

    ##
    # Yields +baseline+, +enhanced+, and the item node per list entry for enhance diagnostics.
    # Consumed by {Test::EnhanceAudit} so the extraction loop has one owner.
    #
    # @yieldparam baseline [Hash]
    # @yieldparam enhanced [Hash]
    # @yieldparam item [Nokogiri::XML::Element]
    # @return [Enumerator] if no block is given
    def each_enhance_pair
      return enum_for(:each_enhance_pair) unless block_given?

      parsed_body.css(items_selector).each do |item|
        baseline = extract_article(item)
        enhanced = enhance_article_hash(baseline.dup, item)
        yield baseline, enhanced, item
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
      select_in_scope(name, item_scope_for(item, base_url))
    end

    ##
    # Selects the value for a given attribute within an existing {ItemScope}.
    # Used by {ItemScope#select} so nested selects reuse one scope per extraction pass.
    #
    # @param name [Symbol, String] Name of the attribute.
    # @param scope [ItemScope] Per-item extraction scope.
    # @return [Object, Array<Object>] The selected value(s).
    # @raise [InvalidSelectorName] If the attribute name is invalid or not defined.
    def select_in_scope(name, scope)
      name = name.to_sym
      raise InvalidSelectorName, "Attribute selector '#{name}' is reserved for items." if name == ITEMS_SELECTOR_KEY

      selector_key, config = selector_config_for(name, allow_nil: name == :url)
      @attribute_selector.call(selector_key, scope:, config:)
    end

    ##
    # Resolves a selector name to +[key, config]+. Used by {CategoriesExtractor}.
    #
    # @param name [Symbol, String]
    # @param allow_nil [Boolean]
    # @return [Array(Symbol, Hash, nil)]
    def selector_config_for(name, allow_nil: false)
      selector_key = name.to_sym

      return [selector_key, @selectors[selector_key]] if @selectors.key?(selector_key)
      return [selector_key, nil] if allow_nil

      raise InvalidSelectorName, "Selector for '#{selector_key}' is not defined."
    end

    private

    attr_reader :response

    def items_selector = @selectors.dig(ITEMS_SELECTOR_KEY, :selector)

    def enhance? = !!@selectors.dig(ITEMS_SELECTOR_KEY, :enhance)

    def parsed_body
      @parsed_body ||= build_parsed_body(response)
    end

    def build_parsed_body(page_response)
      if page_response.json_response?
        fragment = ObjectToXmlConverter.new(page_response.parsed_body).call
        Nokogiri::HTML5.fragment(fragment)
      else
        page_response.parsed_body
      end
    end

    def extract_article(item)
      scope = item_scope_for(item, @url)
      hash = @rss_item_attributes.each_with_object({}) do |selector_key, h|
        value = scope.select(selector_key)
        next if value.nil?

        article_key = SELECTOR_TO_ARTICLE_KEY.fetch(selector_key, selector_key)
        h[article_key] = article_key == :enclosures ? wrap_enclosure_value(value) : value
      end

      hash[:url] ||= default_item_url(item) if anchor_element?(item)
      hash
    end

    def enhance_article_hash(article_hash, article_tag)
      selected_anchor = Html2rss::Html::Navigator.main_anchor_for(article_tag)
      extracted = Html2rss::Html::ArticleExtractor.call(
        article_tag,
        base_url: @url,
        selected_anchor:,
        fallback_anchorless: true,
        time_zone: @time_zone
      )
      return article_hash unless extracted

      extracted.each_with_object(article_hash) do |(key, value), hash|
        next if value.nil? || (hash.key?(key) && hash[key])

        hash[key] = value
      end
    end

    def wrap_enclosure_value(value)
      value.is_a?(Array) ? value : [value]
    end

    def anchor_element?(item)
      item.respond_to?(:name) && item.name.to_s.casecmp('a').zero?
    end

    def default_item_url(item)
      href = item['href'].to_s.strip
      return if href.empty?

      Url.from_relative(href, @url)
    end

    def item_scope_for(item, base_url)
      ItemScope.new(
        item:,
        base_url:,
        scraper: self,
        time_zone: @time_zone
      )
    end
  end
end
