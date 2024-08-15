# frozen_string_literal: true

require 'nokogiri'
require 'parallel'
require 'addressable'

module Html2rss
  ##
  # The AutoSource class is responsible for extracting channel and articles
  # from a given URL.
  # It uses a set of ArticleExtractors to extract articles, utilizing popular ways of
  # marking articles, e.g. schema, microdata, open graph, etc.
  class AutoSource
    class NoArticlesFound < Html2rss::Error; end

    CHANNEL_EXTRACTORS = [
      Channel::Metadata
    ].freeze

    def initialize(url)
      @url = Addressable::URI.parse(url)
    end

    def build
      articles = scrape_articles

      Reducer.call(articles, url:)
      Cleanup.call(articles, url:, keep_different_domain: true)

      raise NoArticlesFound if articles.empty?

      channel = extract_channel

      Html2rss::AutoSource::RssBuilder.new(channel:, articles:).call
    end

    private

    attr_reader :url

    # @return [Nokogiri::HTML::Document]
    def parsed_body
      @parsed_body ||= Nokogiri.HTML(Html2rss::Utils.request_body_from_url(url)).freeze
    end

    def extract_channel
      CHANNEL_EXTRACTORS.each_with_object({}) do |extractor, channel|
        channel.merge!(extractor.new(parsed_body, url:).call)
      end
    end

    # Scrape articles from the parsed body
    # @return [Array<Article>]
    def scrape_articles
      articles = Parallel.flat_map(Scraper.from(parsed_body)) do |klass|
        klass.new(parsed_body, url:).map { |article_hash| Article.new(**article_hash) }
      end

      Log.debug "AutoSource#scrape_articles: #{articles.size}"

      articles
    end
  end
end
