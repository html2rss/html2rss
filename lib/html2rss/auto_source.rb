# frozen_string_literal: true

require 'nokogiri'
require 'parallel'
require 'addressable'

module Html2rss
  ##
  # The AutoSource class automatically extracts articles from a given URL by
  # utilizing a collection of Scrapers. These scrapers analyze and
  # parse popular structured data formats—such as schema, microdata, and
  # open graph—in order to identify relevant article elements accurately and
  # compile them into unified articles.
  # @see Html2rss::AutoSource::Scraper::Schema
  # @see Html2rss::AutoSource::Scraper::SemanticHtml
  #
  # Its plain HTML scraping capabilities are designed to scrape websites
  # without such popular structured data formats. However, the results may vary,
  # depending on the website's structure and its markup.
  # @see Html2rss::AutoSource::Scraper::Html
  class AutoSource
    def initialize(response, _opts = {})
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
