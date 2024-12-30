# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class SelectorsScraper
    include Enumerable

    ITEM_TAGS = %i[title url description author comments updated].freeze

    # def self.articles?(parsed_body)
    #   new(parsed_body, url: '').any?
    # end
    def self.call(url, body:, headers:, selectors: {})
      parsed_body = Nokogiri::HTML(body)

      instance = new(parsed_body, url:, selectors:)
      articles = instance.to_a
      channel = AutoSource::Channel.new(parsed_body, url:, headers:, articles:, stylesheets: [])

      AutoSource::RssBuilder.new(channel:, articles:).call
    end

    def initialize(parsed_body, url:, selectors:)
      @parsed_body = parsed_body
      @url = url
      @selectors = selectors

      raise 'The Selector "url" is reserved and must not be used.' if @selectors.key?(:url)

      @selectors[:url] = selectors.delete(:link)
      @selector_keys = @selectors.keys & Html2rss::AutoSource::Article::PROVIDED_KEYS
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
      value = ItemExtractors.item_extractor_factory(
        @selectors[name].merge(channel: { url: @url }),
        item
      ).get

      if value && (post_process = @selectors.dig(name, :post_process).to_a).any?
        value = post_process(item, name, value, post_process)
      end

      value
    end

    private

    def extract_article(item)
      article_hash = {}

      @selector_keys.each do |key|
        value = select(key, item)
        article_hash[key] = value if value
      end

      Html2rss::AutoSource::Article.new(**article_hash, scraper: self.class)
    end

    def post_process(item, name, value, post_process)
      post_process.each do |object|
        context = Item::Context.new(config: { url: @url },
                                    item:,
                                    options: @selectors[name])

        value = Html2rss::AttributePostProcessors.get_processor(object[:name])
                                                 .new(value, context)
                                                 .get
      end
      # FIXME: allow formatting using SELF
      value
    end
  end
end
