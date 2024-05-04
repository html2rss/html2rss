# frozen_string_literal: true

require 'nokogiri'

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

      channel.reduce({}, :merge)
    end

    def article_extractors
      @article_extractors ||= ARTICLE_EXTRACTORS.select { |extractor| extractor.articles?(parsed_body) }
    end

    def extract_articles(parsed_body)
      raise NoArticleSelectorFound, 'No article extractor found for URL.' if article_extractors.empty?

      articles = article_extractors.flat_map do |extractor|
        extractor.new(parsed_body).call
      rescue StandardError => e
        warn "Error extracting articles from #{url}: #{e.message}"
        # TODO: log error
      end

      # TODO: instead of uniq, try finding duplicates and merge them into one, to get the most information
      articles.uniq! { |article| article[:link] }
      articles.filter! { |article| article[:link]&.to_s != '' }

      articles
    end

    private

    def parsed_body
      return @parsed_body if defined?(@parsed_body)

      body = Html2rss::Utils.request_body_from_url(url)

      @parsed_body = Nokogiri.HTML(body).freeze
    end

    attr_reader :url
  end
end
