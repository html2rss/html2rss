# frozen_string_literal: true

require 'parallel'
require 'dry-validation'
require_relative 'auto_source/configuration'
require_relative 'auto_source/paginator'

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
    DEFAULT_CONFIG = Configuration::DEFAULT_CONFIG
    Config = Configuration::SCHEMA

    def initialize(response, opts = DEFAULT_CONFIG, request_config: {})
      @response = response
      @parsed_body = response.parsed_body
      @url = response.url
      @opts = opts
      @request_strategy = request_config.fetch(:strategy, RequestService.default_strategy_name)
      @request_headers = request_config.fetch(:headers, {}).dup.freeze
    end

    def articles
      @articles ||= extract_articles
    rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
      Log.warn "No auto source scraper found for URL: #{url}. Skipping auto source. (#{error.message})"
      []
    end

    private

    attr_reader :url, :parsed_body, :response, :request_strategy, :request_headers

    def extract_articles
      responses = paginator.responses
      cleanup_options = @opts[:cleanup] || Cleanup::DEFAULT_CONFIG
      base_url = responses.first.url

      Scraper.from(parsed_body, @opts[:scraper]).flat_map do |scraper|
        cleanup_articles_for(scraper, responses, cleanup_options, base_url)
      end
    end

    def run_scraper(instance)
      Parallel.map(instance.each) do |article_hash|
        scraper = instance.class
        Log.debug "Scraper: #{scraper} in worker: #{Parallel.worker_number} [#{article_hash[:url]}]"

        RssBuilder::Article.new(**article_hash, scraper:)
      end
    end

    def cleanup_articles_for(scraper, responses, cleanup_options, base_url)
      scraper_options = scraper_options_for(scraper)

      articles = responses.flat_map do |page_response|
        run_scraper_for_page(scraper, page_response, scraper_options)
      end

      Cleanup.call(articles, url: base_url, **cleanup_options)
    end

    def scraper_options_for(scraper)
      (@opts.dig(:scraper, scraper.options_key) || {}).dup
    end

    def run_scraper_for_page(scraper, page_response, scraper_options)
      instance = scraper.new(page_response.parsed_body, url: page_response.url, **scraper_options)
      run_scraper(instance)
    end

    def paginator
      @paginator ||= Paginator.new(
        response,
        pagination_config: @opts[:pagination],
        default_config: DEFAULT_CONFIG[:pagination],
        request_strategy:,
        request_headers:
      )
    end
  end
end
