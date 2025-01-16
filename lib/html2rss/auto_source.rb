# frozen_string_literal: true

require 'nokogiri'
require 'parallel'
require 'addressable'

module Html2rss
  ##
  # The AutoSource class is responsible for extracting channel and articles
  # from a given URL.
  # It uses a set of ArticleExtractors to extract articles, utilizing popular ways of
  # marking articles, e.g. schema, microdata, open graph, etc.
  class AutoSource
    class NoArticlesFound < Html2rss::Error; end

    def initialize(response, time_zone:, stylesheets: [])
      @response = response
      @url = response.url
      @headers = response.headers
      @time_zone = time_zone
      @stylesheets = stylesheets
    end

    def build
      raise NoArticlesFound if articles.empty?

      Reducer.call(articles, url:)
      Cleanup.call(articles, url:, keep_different_domain: true)

      channel.articles = articles

      Html2rss::RssBuilder.new(
        channel:,
        articles:,
        stylesheets:
      ).call
    end

    def articles
      @articles ||= Scraper.from(parsed_body).flat_map do |scraper|
        instance = scraper.new(parsed_body, url:)

        articles_in_thread = Parallel.map(instance.each) do |article_hash|
          Log.debug "Scraper: #{scraper} in worker: #{Parallel.worker_number} [#{article_hash[:url]}]"

          RssBuilder::Article.new(**article_hash, scraper:)
        end

        Reducer.call(articles_in_thread, url:)

        articles_in_thread
      end
    end

    def channel
      @channel ||= RssBuilder::Channel.new(@response, time_zone: @time_zone)
    end

    private

    attr_reader :url, :stylesheets

    def parsed_body = @response.parsed_body
  end
end
