# frozen_string_literal: true

require 'parallel'
require 'dry-validation'

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
    DEFAULT_CONFIG = {
      scraper: {
        schema: {
          enabled: true
        },
        semantic_html: {
          enabled: true
        },
        html: {
          enabled: true,
          minimum_selector_frequency: Scraper::Html::DEFAULT_MINIMUM_SELECTOR_FREQUENCY
        }
      },
      cleanup: { keep_different_domain: true }
    }.freeze

    Config = Dry::Schema.Params do
      optional(:scraper).hash do
        optional(:schema).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:semantic_html).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:html).hash do
          optional(:enabled).filled(:bool)
          optional(:minimum_selector_frequency).filled(:integer, gt?: 0)
        end
      end

      optional(:cleanup).hash do
        optional(:keep_different_domain).filled(:bool)
      end
    end

    def initialize(response, opts = DEFAULT_CONFIG)
      @parsed_body = response.parsed_body
      @url = response.url
      @opts = opts
    end

    def articles
      @articles ||= extract_articles.tap do |articles|
        Html2rss::AutoSource::Reducer.call(articles, url:)
        Html2rss::AutoSource::Cleanup.call(articles, url:, **@opts[:cleanup])
      end
    rescue Html2rss::AutoSource::Scraper::NoScraperFound
      Log.warn 'No auto source scraper found for the provided URL. Skipping auto source.'
      []
    end

    private

    attr_reader :url, :parsed_body

    def extract_articles
      Scraper.from(parsed_body, @opts[:scraper]).flat_map do |scraper|
        scraper_options = @opts.dig(:scraper, scraper.options_key)

        instance = scraper.new(parsed_body, url:, **scraper_options)

        run_scraper(instance).tap do |articles_in_thread|
          Reducer.call(articles_in_thread, url:)
        end
      end
    end

    def run_scraper(instance)
      Parallel.map(instance.each) do |article_hash|
        scraper = instance.class
        Log.debug "Scraper: #{scraper} in worker: #{Parallel.worker_number} [#{article_hash[:url]}]"

        RssBuilder::Article.new(**article_hash, scraper:)
      end
    end
  end
end
