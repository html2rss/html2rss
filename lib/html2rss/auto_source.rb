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
    class UnsupportedUrlScheme < Html2rss::Error; end
    class NoArticlesFound < Html2rss::Error; end

    SUPPORTED_URL_SCHEMES = %w[http https].to_set.freeze

    def initialize(url)
      unless url.is_a?(String) || url.is_a?(Addressable::URI)
        raise ArgumentError,
              'URL must be a String or Addressable::URI'
      end

      @url = Addressable::URI.parse(url)

      raise ArgumentError, 'URL must be absolute' unless @url.absolute?
      raise UnsupportedUrlScheme, "#{@url.scheme} not supported" unless SUPPORTED_URL_SCHEMES.include?(@url.scheme)
    end

    def build
      assert_articles_found!

      Reducer.call(articles, url:)
      Cleanup.call(articles, url:, keep_different_domain: true)

      Html2rss::AutoSource::RssBuilder.new(
        channel:,
        articles:
      ).call
    end

    def articles
      @articles ||= Parallel.flat_map(Scraper.from(parsed_body)) do |scraper|
        articles_in_thread = scraper.new(parsed_body, url:)
                                    .map { |article_hash| Article.new(**article_hash, scraper:) }
        Reducer.call(articles_in_thread, url:)
        articles_in_thread
      end
    end

    def channel
      Channel.new(parsed_body, response:, url:, articles:)
    end

    private

    attr_reader :url

    def response
      @response ||= Html2rss::Utils.request_url(url)
    end

    # Parses the HTML body of the response using Nokogiri.
    # @return [Nokogiri::HTML::Document]
    def parsed_body
      @parsed_body ||= Nokogiri.HTML(response.body).freeze
    end

    def assert_articles_found!
      raise NoArticlesFound if articles.empty?

      Log.debug "AutoSource#assert_articles_found! #{articles.size}"
    end
  end
end
