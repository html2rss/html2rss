# frozen_string_literal: true

require 'parallel'
require 'dry-validation'

module Html2rss
  ##
  # The AutoSource class automatically extracts articles from a given URL by
  # utilizing a collection of Scrapers. These scrapers analyze and
  # parse popular structured data formats—such as schema, microdata, and
  # open graph—to identify and compile article elements into unified articles.
  #
  # Scrapers supporting plain HTML are also available for sites without structured data,
  # though results may vary based on page markup.
  #
  # @see Html2rss::AutoSource::Scraper::Schema
  # @see Html2rss::AutoSource::Scraper::SemanticHtml
  # @see Html2rss::AutoSource::Scraper::Html
  class AutoSource
    DEFAULT_CONFIG = {
      scraper: {
        schema: {
          enabled: true
        },
        json_state: {
          enabled: true
        },
        semantic_html: {
          enabled: true
        },
        html: {
          enabled: true,
          minimum_selector_frequency: Scraper::Html::DEFAULT_MINIMUM_SELECTOR_FREQUENCY,
          use_top_selectors: Scraper::Html::DEFAULT_USE_TOP_SELECTORS
        },
        rss_feed_detector: {
          enabled: true
        }
      },
      cleanup: Cleanup::DEFAULT_CONFIG
    }.freeze

    Config = Dry::Schema.Params do
      optional(:scraper).hash do
        optional(:schema).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:json_state).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:semantic_html).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:html).hash do
          optional(:enabled).filled(:bool)
          optional(:minimum_selector_frequency).filled(:integer, gt?: 0)
          optional(:use_top_selectors).filled(:integer, gt?: 0)
        end
        optional(:rss_feed_detector).hash do
          optional(:enabled).filled(:bool)
        end
      end

      optional(:cleanup).hash do
        optional(:keep_different_domain).filled(:bool)
        optional(:min_words_title).filled(:integer, gt?: 0)
      end
    end

    def initialize(response, opts = DEFAULT_CONFIG)
      @parsed_body = response.parsed_body
      @url = response.url
      @opts = opts
    end

    def articles
      @articles ||= extract_articles
    rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
      Log.warn "No auto source scraper found for URL: #{url}. Skipping auto source. (#{error.message})"
      []
    end

    private

    attr_reader :url, :parsed_body

    def extract_articles
      Scraper.from(parsed_body, @opts[:scraper]).flat_map do |scraper|
        scraper_options = @opts.dig(:scraper, scraper.options_key)

        instance = scraper.new(parsed_body, url:, **scraper_options)

        articles = run_scraper(instance)
        Cleanup.call(articles, url:, **@opts[:cleanup])
        articles
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
