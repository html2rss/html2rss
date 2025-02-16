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
    # A context instance is passed to Item Extractors.
    Context = Struct.new('Context', :options, :item, :config, :scraper, keyword_init: true)

    DEFAULT_CONFIG = { items: { enhance: true } }.freeze

    ITEMS_SELECTOR_KEY = :items
    ITEM_TAGS = %i[title url description author comments published_at guid enclosure categories].freeze
    SPECIAL_ATTRIBUTES = Set[:guid, :enclosure, :categories].freeze

    ##
    # Keep backward compatibility.
    #
    # key: new name, value: previous name
    RENAMED_ATTRIBUTES = { published_at: %i[updated pubDate] }.freeze

    ##
    # Initializes a new Selectors instance.
    #
    # @param response [RequestService::Response] The response object.
    # @param selectors [Hash] The selectors hash.
    # @param time_zone [String] The time zone to use for date parsing.
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

    def articles
      @articles ||= @selectors.dig(ITEMS_SELECTOR_KEY, :order) == 'reverse' ? to_a.tap(&:reverse!) : to_a
    end

    ##
    # @yield [Hash] Each scraped article_hash
    # @return [Array<Html2rss::RssBuilder::Article>] the scraped articles
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

    # @return [Html2rss::RssBuilder::Article] the extracted article.
    def extract_article(item)
      @rss_item_attributes.to_h { |key| [key, select(key, item)] }.compact
    end

    ##
    # Enhances the article hash with auto_source's semantic HTML extraction.
    # Keeps existing values and only adds new ones.
    # This method is called only if the `enhance` option is set to true.
    #
    # @param article_hash [Hash] The article hash to enhance.
    # @param item [Nokogiri::XML::Element] The item from which to extract additional attributes.
    # @return [Hash] The enhanced article_hash.
    def enhance_article_hash(article_hash, item)
      extracted = AutoSource::Scraper::SemanticHtml::Extractor.new(item, url: @url).call

      return article_hash unless extracted

      extracted.each_with_object(article_hash) do |(key, value), hash|
        next if value.nil?
        next if article_hash.key?(key) && !hash[key].nil?

        hash[key] = value
      end
    end

    ##
    # Selects the value for a given attribute name from the item.
    #
    # @param name [Symbol, String] The name of the attribute to select.
    # @param item [Nokogiri::XML::Element] The item from which to select the attribute.
    # @return [Object, Array<Object>] The selected value(s) for the attribute.
    def select(name, item)
      name = name.to_sym

      raise InvalidSelectorName, "`#{name}` is not an attribute selector" if name == ITEMS_SELECTOR_KEY
      raise InvalidSelectorName, "`#{name}` is not defined" unless @selectors[name]

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

          Html2rss::Log.warn "Selector `#{old_name}` is deprecated. Please rename to `#{new_name}`."
          @selectors[new_name] ||= @selectors.delete(old_name)
        end
      end
    end

    def parsed_body
      return response.parsed_body unless response.json_response?

      Nokogiri::HTML5.fragment ObjectToXmlConverter.new(response.parsed_body).call
    end

    def select_special(name, item)
      selector = @selectors[name]

      case name
      when :enclosure
        enclosure(item, selector)
      when :guid, :categories
        Array(selector).map { |selector_name| select(selector_name, item) }
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

    # @return [Enclosure] enclosure details.
    def enclosure(item, selector)
      url = Html2rss::Utils.build_absolute_url_from_relative(select_regular(:enclosure, item), @url)

      Html2rss::RssBuilder::Enclosure.new(url:, type: selector[:content_type])
    end
  end
end
