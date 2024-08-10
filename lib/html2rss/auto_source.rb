# frozen_string_literal: true

require 'nokogiri'
require 'parallel'

module Html2rss
  ##
  # The AutoSource class is responsible for extracting channel and articles
  # from a given URL.
  # It uses a set of ArticleExtractors to extract articles, utilizing popular ways of
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

    def self.deduplicate_by_url!(articles)
      articles.uniq! { |article| article[:url] }
    end

    def self.keep_only_http_urls!(articles)
      articles.select! { |article| article[:url].to_s.start_with?('http') }
    end

    def self.remove_titleless_articles!(articles)
      articles.reject! { |article| article[:title].to_s.strip.empty? }
    end

    def self.remove_one_word_title_articles!(articles)
      articles.reject! do |article|
        title = article[:title].to_s.strip
        title.empty? || title.split.size < 2
      end
    end

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

    private

    attr_reader :url

    def parsed_body
      @parsed_body ||= Nokogiri.HTML(Html2rss::Utils.request_body_from_url(url)).freeze
    end

    def extract_channel(parsed_body)
      CHANNEL_EXTRACTORS.each_with_object({}) do |extractor, channel|
        channel.merge!(extractor.new(parsed_body, url:).call)
      end
    end

    def article_extractors
      available_extractors = ARTICLE_EXTRACTORS.select { |extractor| extractor.articles?(parsed_body) }
      raise NoArticleSelectorFound, 'No article extractor found for URL.' if available_extractors.empty?

      available_extractors
    end

    def extract_articles(parsed_body)
      Parallel.flat_map(article_extractors) { |extractor| extractor.new(parsed_body).call }
    end
  end
end
