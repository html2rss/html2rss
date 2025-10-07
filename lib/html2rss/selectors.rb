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
  class Selectors # rubocop:disable Metrics/ClassLength
    class InvalidSelectorName < Html2rss::Error; end

    include Enumerable

    # A context instance passed to item extractors and post-processors.
    Context = Struct.new('Context', :options, :item, :config, :scraper, keyword_init: true)

    DEFAULT_CONFIG = { items: { enhance: true } }.freeze

    ITEMS_SELECTOR_KEY = :items
    ITEM_TAGS = %i[title url description author comments published_at guid enclosure categories].freeze
    SPECIAL_ATTRIBUTES = Set[:guid, :enclosure, :categories].freeze

    # Mapping of new attribute names to their legacy names for backward compatibility.
    RENAMED_ATTRIBUTES = { published_at: %i[updated pubDate] }.freeze

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

      validate_url_and_link_exclusivity!
      fix_url_and_link!
      handle_renamed_attributes!

      @rss_item_attributes = @selectors.keys & Html2rss::RssBuilder::Article::PROVIDED_KEYS
    end

    ##
    # Returns articles extracted from the response.
    # Reverses order if config specifies reverse ordering.
    #
    # @return [Array<Html2rss::RssBuilder::Article>]
    def articles
      @articles ||= @selectors.dig(ITEMS_SELECTOR_KEY, :order) == 'reverse' ? to_a.tap(&:reverse!) : to_a
    end

    ##
    # Iterates over each scraped article.
    #
    # @yield [article] Gives each article as an Html2rss::RssBuilder::Article.
    # @return [Enumerator] An enumerator if no block is given.
    def each(&)
      return enum_for(:each) unless block_given?

      enhance = enhance?

      parsed_body.css(items_selector).each do |item|
        article_hash = extract_article(item)

        enhance_article_hash(article_hash, item) if enhance

        yield Html2rss::RssBuilder::Article.new(**article_hash, scraper: self.class)
      end
    end

    ##
    # Returns the CSS selector for the items.
    # @return [String] the CSS selector for the items
    def items_selector = @selectors.dig(ITEMS_SELECTOR_KEY, :selector)

    ## @return [Boolean] whether to enhance the article hash with auto_source's semantic HTML extraction.
    def enhance? = !!@selectors.dig(ITEMS_SELECTOR_KEY, :enhance)

    ##
    # Extracts an article hash for a given item element.
    #
    # @param item [Nokogiri::XML::Element] The element to extract from.
    # @return [Hash] Hash of attributes for the article.
    def extract_article(item)
      @rss_item_attributes.to_h { |key| [key, select(key, item)] }.compact
    end

    ##
    # Enhances the article hash using semantic HTML extraction.
    # Only adds keys that are missing from the original hash.
    #
    # @param article_hash [Hash] The original article hash.
    # @param article_tag [Nokogiri::XML::Element] HTML element to extract additional info from.
    # @return [Hash] The enhanced article hash.
    def enhance_article_hash(article_hash, article_tag)
      extracted = HtmlExtractor.new(article_tag, base_url: @url).call
      return article_hash unless extracted

      extracted.each_with_object(article_hash) do |(key, value), hash|
        next if value.nil? || (hash.key?(key) && hash[key])

        hash[key] = value
      end
    end

    ##
    # Selects the value for a given attribute from an HTML element.
    #
    # @param name [Symbol, String] Name of the attribute.
    # @param item [Nokogiri::XML::Element] The HTML element to process.
    # @return [Object, Array<Object>] The selected value(s).
    # @raise [InvalidSelectorName] If the attribute name is invalid or not defined.
    def select(name, item)
      name = name.to_sym

      raise InvalidSelectorName, "Attribute selector '#{name}' is reserved for items." if name == ITEMS_SELECTOR_KEY

      raise InvalidSelectorName, "Selector for '#{name}' is not defined." unless @selectors.key?(name)

      SPECIAL_ATTRIBUTES.member?(name) ?  select_special(name, item) : select_regular(name, item)
    end

    private

    attr_reader :response

    def validate_url_and_link_exclusivity!
      return unless @selectors.key?(:url) && @selectors.key?(:link)

      raise InvalidSelectorName, 'You must either use "url" or "link" your selectors. Using both is not supported.'
    end

    def fix_url_and_link!
      return if @selectors[:url] || !@selectors.key?(:link)

      @selectors = @selectors.dup
      @selectors[:url] = @selectors[:link]
    end

    def handle_renamed_attributes!
      RENAMED_ATTRIBUTES.each_pair do |new_name, old_names|
        old_names.each do |old_name|
          next unless @selectors.key?(old_name)

          Html2rss::Log.warn("Selector '#{old_name}' is deprecated. Please rename to '#{new_name}'.")
          @selectors[new_name] ||= @selectors.delete(old_name)
        end
      end
    end

    def parsed_body
      @parsed_body ||= if response.json_response?
                         fragment = ObjectToXmlConverter.new(response.parsed_body).call
                         Nokogiri::HTML5.fragment(fragment)
                       else
                         response.parsed_body
                       end
    end

    def select_special(name, item)
      selector = @selectors[name]

      case name
      when :enclosure
        enclosure(item, selector)
      when :guid
        Array(selector).map { |selector_name| select(selector_name, item) }
      when :categories
        select_categories(selector, item)
      end
    end

    def select_regular(name, item)
      selector = @selectors[name]

      value = Extractors.get(selector.merge(channel: { url: @url, time_zone: @time_zone }), item)

      if value && (post_process_steps = @selectors.dig(name, :post_process))
        post_process_steps = [post_process_steps] unless post_process_steps.is_a?(Array)

        value = post_process(item, value, post_process_steps)
      end

      value
    end

    def post_process(item, value, post_process_steps)
      post_process_steps.each do |options|
        context = Context.new(config: { channel: { url: @url, time_zone: @time_zone } },
                              item:, scraper: self, options:)

        value = PostProcessors.get(options[:name], value, context)
      end

      value
    end

    def select_categories(category_selectors, item)
      Array(category_selectors).flat_map do |selector_name|
        extract_category_values(selector_name, item)
      end
    end

    def extract_category_values(selector_name, item)
      selector_key = selector_name.to_sym
      config = @selectors[selector_key]
      return [] unless config

      nodes = Extractors.element(item, config[:selector])
      return Array(select_regular(selector_key, item)) unless node_set_with_multiple_elements?(nodes)

      Array(nodes).flat_map { |node| extract_categories_from_node(node, config, item) }
    end

    def extract_categories_from_node(node, config, item)
      values = Extractors.get(category_node_options(config), node)
      values = apply_post_process_steps(item, values, config[:post_process])

      Array(values).filter_map { |category| extract_category_text(category) }
    end

    def extract_category_text(category)
      text = case category
             when Nokogiri::XML::Node, Nokogiri::XML::NodeSet
               HtmlExtractor.extract_visible_text(category)
             else
               category&.to_s
             end

      stripped = text&.strip
      stripped unless stripped.nil? || stripped.empty?
    end

    def node_set_with_multiple_elements?(nodes)
      nodes.is_a?(Nokogiri::XML::NodeSet) && nodes.length > 1
    end

    def category_node_options(selector_config)
      selector_config.merge(channel: { url: @url, time_zone: @time_zone }, selector: nil)
    end

    def apply_post_process_steps(item, value, post_process_steps)
      return value unless value && post_process_steps

      steps = post_process_steps.is_a?(Array) ? post_process_steps : [post_process_steps]
      post_process(item, value, steps)
    end

    # @return [Hash] enclosure details.
    def enclosure(item, selector)
      url = Url.from_relative(select_regular(:enclosure, item), @url)

      { url:, type: selector[:content_type] }
    end
  end
end
