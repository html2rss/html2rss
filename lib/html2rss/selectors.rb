# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  ##
  # Scrapes articles from a given HTML page using CSS selectors.
  # This selector parses the traditional 'feed configs' which html2rss was launched with.
  class Selectors
    class InvalidSelectorName < Html2rss::Error; end

    include Enumerable
    # A context instance is passed to Item Extractors.
    Context = Struct.new('Context', :options, :item, :config, :scraper, keyword_init: true)

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
      @articles ||= @selectors.dig(:items, :order) == 'reverse' ? to_a.tap(&:reverse!) : to_a
    end

    ##
    # @yield [Hash] Each scraped article_hash
    # @return [Array<Html2rss::RssBuilder::Article>] the scraped articles
    def each(&)
      return enum_for(:each) unless block_given?

      parsed_body.css(items_selector).each do |item|
        if (article = extract_article(item))
          yield article
        end
      end
    end

    ##
    # Returns the CSS selector for the items.
    # @return [String] the CSS selector for the items
    def items_selector = @selectors.dig(:items, :selector)

    # @return [Html2rss::RssBuilder::Article] the extracted article.
    def extract_article(item)
      article_hash = {}

      @rss_item_attributes.each_with_object(article_hash) do |key, hash|
        value = select(key, item)
        hash[key] = value
      end.compact!

      Html2rss::RssBuilder::Article.new(**article_hash, scraper: self.class)
    end

    ##
    # Selects the value for a given attribute name from the item.
    #
    # @param name [Symbol, String] The name of the attribute to select.
    # @param item [Nokogiri::XML::Element] The item from which to select the attribute.
    # @return [Object, Array<Object>] The selected value(s) for the attribute.
    def select(name, item)
      name = name.to_sym

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

      # Converting JSON to XML is a feature that is limited to this scraper
      converted_body = ObjectToXmlConverter.new(JSON.parse(response.body, symbolize_names: true)).call

      Nokogiri::HTML5.fragment converted_body
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

      value = ItemExtractors.item_extractor_factory(selector.merge(channel: { url: @url, time_zone: @time_zone }),
                                                    item).get

      if value && (post_process_steps = @selectors.dig(name, :post_process))
        post_process_steps = [post_process_steps] unless post_process_steps.is_a?(Array)

        value = post_process(item, value, post_process_steps)
      end

      value
    end

    def post_process(item, value, post_process_steps)
      post_process_steps.each do |options|
        options = Hash.try_convert(options)

        context = Context.new(config: { channel: { url: @url, time_zone: @time_zone } },
                              item:, scraper: self, options:)

        value = Html2rss::Selectors::AttributePostProcessors.get_processor(options[:name]).get(value, context)
      end

      value
    end

    # @return [Enclosure] enclosure details.
    def enclosure(item, selector)
      item_url = select_regular(:enclosure, item)

      url = Html2rss::Utils.build_absolute_url_from_relative(item_url, @url)
      type = selector[:content_type]

      Html2rss::RssBuilder::Enclosure.new(url:, type:)
    end
  end
end
