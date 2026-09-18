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
  class Selectors # rubocop:disable Metrics/ClassLength -- public API + private field dispatch
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

      selector_key, config = selector_config_for(name, allow_nil: name == :url)
      select_field(selector_key, scope:, config:)
    end

    ##
    # Resolves a selector name to +[key, config]+. Used by category field dispatch.
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
        fragment = JsonXml.new(page_response.parsed_body).call
        Nokogiri::HTML5.fragment(fragment)
      else
        page_response.parsed_body
      end
    end

    def extract_article(item)
      scope = item_env_for(item, @url)
      hash = @rss_item_attributes.each_with_object({}) do |selector_key, h|
        value = scope.select(selector_key)
        next if value.nil?

        article_key = SELECTOR_TO_ARTICLE_KEY.fetch(selector_key, selector_key)
        h[article_key] = article_key == :enclosures ? wrap_enclosure_value(value) : value
      end

      hash[:url] ||= default_item_url(item) if anchor_element?(item)
      hash
    end

    def enhance_article_hash(article_hash, article_tag) # rubocop:disable Metrics/MethodLength -- merge extracted keys
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

    def select_field(selector_key, scope:, config:)
      return default_item_url(scope.item, scope.base_url) if fallback_url_selector?(selector_key, config, scope.item)
      raise InvalidSelectorName, "Selector for '#{selector_key}' is not defined." if config.nil?

      if SPECIAL_ATTRIBUTES.member?(selector_key)
        select_special(selector_key, scope:, config:)
      else
        select_regular(selector_key, scope:, config:)
      end
    end

    def select_special(name, scope:, config:)
      case name
      when :enclosure
        enclosure(scope:, config:)
      when :guid
        Array(config).map { |selector_name| scope.select(selector_name) }
      when :categories
        select_categories(category_selectors: config, scope:)
      end
    end

    def select_regular(_name, scope:, config:)
      merged_config = config.merge(base_url: scope.base_url)
      value = Extractors.get(merged_config, scope.item)

      apply_post_process_steps(scope:, value:, post_process_steps: config[:post_process])
    end

    def apply_post_process_steps(scope:, value:, post_process_steps:)
      return value unless value && post_process_steps

      steps = post_process_steps.is_a?(Array) ? post_process_steps : [post_process_steps]
      post_process(scope, value, steps)
    end

    def post_process(scope, value, post_process_steps)
      post_process_steps.each do |options|
        value = PostProcessors.get(options[:name], value, scope.context_for(options:))
      end

      value
    end

    # Flattens configured category selector names into discrete category strings.
    # When a selector matches multiple nodes, each node is extracted independently
    # (with optional post-processors) so multi-tag UIs become multiple categories.
    #
    # @param category_selectors [Array, String, Symbol]
    # @param scope [ItemEnv]
    # @return [Array<String>]
    def select_categories(category_selectors:, scope:)
      Array(category_selectors).flat_map do |selector_name|
        extract_category_values(selector_name, scope:)
      end
    end

    def extract_category_values(selector_name, scope:)
      _selector_key, config = selector_config_for(selector_name, allow_nil: true)
      return [] unless config

      nodes = extract_nodes(item: scope.item, config:)
      return Array(scope.select(selector_name)) unless node_set_with_multiple_elements?(nodes)

      Array(nodes).flat_map { |node| extract_categories_from_node(node, scope:, config:) }
    end

    def extract_categories_from_node(node, scope:, config:)
      values = Extractors.get(config.merge(base_url: scope.base_url, selector: nil), node)
      values = apply_post_process_steps(scope:, value: values, post_process_steps: config[:post_process])

      Array(values).filter_map { |category| extract_category_text(category) }
    end

    def extract_category_text(category)
      text = case category
             when Nokogiri::XML::Node, Nokogiri::XML::NodeSet
               Html2rss::Html::Navigator.extract_visible_text(category)
             else
               category&.to_s
             end

      stripped = text&.strip
      stripped unless stripped.nil? || stripped.empty?
    end

    def node_set_with_multiple_elements?(nodes)
      nodes.is_a?(Nokogiri::XML::NodeSet) && nodes.length > 1
    end

    def extract_nodes(item:, config:)
      return unless config.respond_to?(:[]) && config[:selector]

      Extractors.element(item, config[:selector])
    end

    # @return [Hash, nil] enclosure details, or nil when the selector yields nothing.
    def enclosure(scope:, config:)
      selected = select_regular(:enclosure, scope:, config:)
      return if selected.nil? || selected.to_s.strip.empty?

      url = Url.from_relative(selected, scope.base_url)

      { url:, type: config[:content_type] }
    end

    def fallback_url_selector?(selector_key, config, item)
      selector_key == :url && config.nil? && anchor_element?(item)
    end

    def anchor_element?(item)
      item.respond_to?(:name) && item.name.to_s.casecmp('a').zero?
    end

    def default_item_url(item, base_url = @url)
      href = item['href'].to_s.strip
      return if href.empty?

      Url.from_relative(href, base_url)
    end

    def item_env_for(item, base_url)
      ItemEnv.new(
        item:,
        base_url:,
        scraper: self,
        time_zone: @time_zone
      )
    end
  end
end
