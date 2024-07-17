# frozen_string_literal: true

require 'nokogiri'
require 'parallel'

module Html2rss
  ##
  # The AutoSource class is responsible for extracting channel and articles
  # from (just) a given URL.
  # It uses a set of ArticleExtractors to extract articles, using utilizing popular ways of
  # marking articles, e.g. schema, microdata, open graph, etc.
  class AutoSource
    class NoArticleSelectorFound < StandardError; end

    CHANNEL_EXTRACTORS = [
      Channel::Metadata
    ].freeze

    ARTICLE_EXTRACTORS = [
      JsonLd,
      SemanticHtml
    ].freeze

    def initialize(url)
      @url = url
    end

    def call
      {
        channel: extract_channel(parsed_body),
        articles: extract_articles(parsed_body)
      }
    end

    def to_rss
      Html2rss::AutoSource::RssBuilder.new(url:, **call).call
    end

    def extract_channel(parsed_body)
      channel = CHANNEL_EXTRACTORS.map do |extractor|
        extractor.new(parsed_body, url:).call
      end

      # TODO: extract TTL from Cache Control / Expires header from HTTP response
      channel.reduce({}, :merge)
    end

    def article_extractors
      article_extractors = ARTICLE_EXTRACTORS.select { |extractor| extractor.articles?(parsed_body) }

      raise NoArticleSelectorFound, 'No article extractor found for URL.' if article_extractors.empty?

      article_extractors
    end

    def extract_articles(parsed_body)
      Parallel.flat_map(article_extractors) { |extractor| extractor.new(parsed_body).call }
    end

    ##
    # Provides a way for sourcers to deduplicate articles based on their URL.
    def self.deduplicate_by_url!(articles)
      # articles.reject! { |article| article[:url].to_s.empty? }
      articles.uniq! { |article| article[:url] }
      articles
    end

    def self.keep_only_http_urls!(articles)
      string = 'http'

      articles.select! { |article| article[:url].to_s.start_with?(string) }

      articles
    end

    def self.remove_titleless_articles!(articles)
      articles.reject! { |article| article[:title].nil? || article[:title].empty? }
      articles
    end

    def self.remove_one_word_title_articles!(articles)
      articles.reject! do |article|
        article[:title].nil? ||
          article[:title].empty? ||
          article[:title].count(' ') < 1
      end
      articles
    end

    private

    def parsed_body
      return @parsed_body if defined?(@parsed_body)

      # TODO: add headers to request, use Global config
      body = Html2rss::Utils.request_body_from_url(url)

      @parsed_body = Nokogiri.HTML(body).freeze
    end

    attr_reader :url
  end
end
