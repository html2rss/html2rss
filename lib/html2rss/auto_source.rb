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

    class HTMLMetadata
      def initialize(parsed_body, url:)
        @url = url
        @parsed_body = parsed_body
      end

      def call
        {
          url:,
          title: parsed_body.css('title').text,
          language: parsed_body.css('html').attr('lang').value,
          description: parsed_body.css('meta[name="description"]').attr('content').value
        }
      end

      private

      attr_reader :parsed_body, :url
    end

    CHANNEL_EXTRACTORS = [
      HTMLMetadata
    ]

    ARTICLE_EXTRACTORS = [
      NewsArticleMicrodata
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
      raise NoArticleSelectorFound, 'No extractor found articles.' if article_extractors.empty?

      article_extractors.flat_map { |extractor| extractor.new(parsed_body).call }
    end

    private

    def parsed_body
      return @parsed_body if defined?(@parsed_body)

      body = Html2rss::Utils.request_body_from_url(url)

      @parsed_body = Nokogiri.HTML(body)
    end

    attr_reader :url
  end
end
