# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  ##
  # Scrapes articles from a given HTML page using CSS selectors.
  # This selector parses the traditional 'feed configs' which html2rss was launched with.
  class SelectorsScraper
    class InvalidSelectorName < Html2rss::Error; end

    include Enumerable

    ITEM_TAGS = %i[title url description author comments updated guid enclosure categories].freeze

    SPECIAL_ATTRIBUTES = Set[:guid, :enclosure, :categories].freeze

    ##
    # Keep backward compatibility.
    #
    # key: new name, value: previous name
    RENAMED_ATTRIBUTES = {
      published_at: %i[updated pubDate]
    }.freeze

    # def self.articles?(parsed_body)
    #   new(parsed_body, url: '').any?
    # end

    def self.call(url, body:, headers:, selectors: {}, channel: {}, stylesheets: [], params: {})
      parsed_body = if headers['content-type']&.include?('application/json')
                      Nokogiri::HTML5.fragment Html2rss::ObjectToXmlConverter.new(JSON.parse(body)).call
                    else
                      Nokogiri::HTML(body)
                    end

      channel = DynamicParams.call(channel, params)
      time_zone = channel[:time_zone]

      articles = new(parsed_body, url:, selectors:, time_zone:).to_a
      articles.reverse! if selectors.dig(:items, :order) == 'reverse'

      channel = AutoSource::Channel.new(parsed_body, url:,
                                                     headers:,
                                                     overrides: channel,
                                                     time_zone:)

      AutoSource::RssBuilder.new(channel:, articles:, stylesheets:).call
    end

    def initialize(parsed_body, url:, selectors:, time_zone:)
      @parsed_body = parsed_body
      @url = url
      @selectors = selectors
      @time_zone = time_zone || 'UTC'

      if @selectors.key?(:url) && @selectors.key?(:link)
        raise 'You must either use "url" or "link". Using both is not supported.'
      end

      if !selectors[:url] && selectors.key?(:link)
        @selectors = @selectors.dup
        @selectors[:url] = selectors[:link]
      end

      RENAMED_ATTRIBUTES.each_pair do |new_name, old_names|
        old_names.each do |old_name|
          next unless @selectors.key?(old_name)

          Html2rss::Log.warn "Selector `#{old_name}` is deprecated. Please rename to `#{new_name}`."
          @selectors[new_name] ||= @selectors.delete(old_name)
        end
      end

      @rss_item_attributes = @selectors.keys & Html2rss::AutoSource::Article::PROVIDED_KEYS
    end

    ##
    # @yield [Hash] Each scraped article_hash
    # @return [Array<Article>] the scraped article_hashes
    def each(&)
      enum_for(:each) unless block_given?

      @parsed_body.css(items_selector).each do |item|
        if (article = extract_article(item))
          yield article
        end
      end
    end

    def items_selector = @selectors.dig(:items, :selector)

    def select(name, item)
      name = name.to_sym
      Log.debug "#{self.class}#select(#{name}, #{item.class})"

      if SPECIAL_ATTRIBUTES.member?(name)
        select_special(name, item)
      else
        select_regular(name, item)
      end
    end

    private

    def select_special(name, item)
      selector = @selectors[name]

      case name
      when :enclosure
        enclosure(item, selector)
      when :guid, :categories
        selector.map { |selector_name| select(selector_name, item) }
      end
    end

    def select_regular(name, item)
      raise InvalidSelectorName, "`#{name}` is not defined" unless @selectors[name]

      value = ItemExtractors.item_extractor_factory(
        @selectors[name].merge(channel: { url: @url, time_zone: @time_zone }),
        item
      ).get

      if value && (post_process = @selectors.dig(name, :post_process))
        post_process = [post_process] unless post_process.is_a?(Array)

        value = post_process(item, value, post_process)
      end

      value
    end

    def extract_article(item)
      article_hash = {}

      @rss_item_attributes.each do |key|
        value = select(key, item)
        article_hash[key] = value if value
      end

      Html2rss::AutoSource::Article.new(**article_hash, scraper: self.class)
    end

    def post_process(item, value, post_process)
      post_process.each do |object|
        object = [object].to_h unless object.is_a?(Hash)

        context = Item::Context.new(config: { channel: { url: @url, time_zone: @time_zone } },
                                    item:,
                                    scraper: self,
                                    options: object)

        value = Html2rss::AttributePostProcessors.get_processor(object[:name])
                                                 .new(value, context)
                                                 .get
      end

      value
    end

    # @return [Enclosure] enclosure details.
    def enclosure(item, selector)
      item_url = select_regular(:enclosure, item)

      url = Html2rss::Utils.build_absolute_url_from_relative(item_url, @url)
      type = selector[:content_type]

      Html2rss::Enclosure.new(url:, type:)
    end
  end
end
