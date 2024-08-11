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
    CHANNEL_EXTRACTORS = [
      Channel::Metadata
    ].freeze

    def initialize(url)
      @url = Addressable::URI.parse(url)
    end

    def build
      Html2rss::AutoSource::RssBuilder.new(
        url:,
        channel: extract_channel,
        articles: scrape_articles.then do |articles|
                    Reducer.call(articles, url:)
                    Cleanup.call(articles, url:)
                  end
      ).call
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

    # @return [Array<Article>]
    def scrape_articles
      article_hashes = Parallel.flat_map(Scraper.from(parsed_body)) do |klass|
        klass.new(parsed_body, url:).call
      end

      article_hashes.map! { |article_hash| Article.new(**article_hash) }

      article_hashes
    end
  end
end
