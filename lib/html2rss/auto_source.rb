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
    ##
    # Error raised when no article extractor selector is found.
    class NoArticleExtractorFound < Html2rss::Error; end

    CHANNEL_EXTRACTORS = [
      Channel::Metadata
    ].freeze

    ARTICLE_EXTRACTORS = [
      JsonLd,
      SemanticHtml
    ].freeze

    def initialize(url)
      @url = Addressable::URI.parse(url)
    end

    def call
      sourced = {
        channel: extract_channel(parsed_body),
        articles: extract_articles(parsed_body)
      }

      sourced[:articles] = Cleanup.call(sourced[:articles], url:)

      sourced
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
      ARTICLE_EXTRACTORS.select { |extractor| extractor.articles?(parsed_body) }
                        .tap do |available_extractors|
        raise NoArticleExtractorFound, 'No article extractor found for URL.' if available_extractors.empty?
      end
    end

    # @return [Array<Article>]
    def extract_articles(parsed_body)
      article_hashes = Parallel.flat_map(article_extractors) do |extractor|
        extractor.new(parsed_body, url: @url).call
      end

      article_hashes.map! { |article_hash| Article.new(**article_hash) }

      article_hashes
    end
  end
end
