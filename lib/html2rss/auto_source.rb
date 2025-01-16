# frozen_string_literal: true

require 'nokogiri'
require 'parallel'
require 'addressable'

module Html2rss
  ##
  # The AutoSource class is responsible for automatically extracting articles
  # from a given URL.
  # It uses a set of ArticleExtractors to extract articles, utilizing popular ways of
  # marking articles, e.g. schema, microdata, open graph, etc.
  class AutoSource
    def initialize(response)
      @parsed_body = response.parsed_body
      @url = response.url
    end

    def articles
      @articles ||= extract_articles.tap do |articles|
        Html2rss::AutoSource::Reducer.call(articles, url:)
        Html2rss::AutoSource::Cleanup.call(articles, url:, keep_different_domain: true)
      end
    rescue Html2rss::AutoSource::Scraper::NoScraperFound
      Log.warn 'No auto source scraper found for the provided URL. Skipping auto source.'
      []
    end

    private

    attr_reader :url, :parsed_body

    def extract_articles
      Scraper.from(parsed_body).flat_map do |scraper|
        instance = scraper.new(parsed_body, url:)

        articles_in_thread = Parallel.map(instance.each) do |article_hash|
          Log.debug "Scraper: #{scraper} in worker: #{Parallel.worker_number} [#{article_hash[:url]}]"

          RssBuilder::Article.new(**article_hash, scraper:)
        end

        Reducer.call(articles_in_thread, url:)

        articles_in_thread
      end
    end
  end
end
