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

    ##
    # @param url [Addressable::URI] The URL to extract articles from.
    # @param body [String] The body of the response.
    # @param headers [Hash] The headers of the response.
    def initialize(url, body:, headers: {})
      raise ArgumentError, 'URL must be a Addressable::URI' unless url.is_a?(Addressable::URI)
      raise ArgumentError, 'URL must be absolute' unless url.absolute?
      raise UnsupportedUrlScheme, "#{url.scheme} not supported" unless SUPPORTED_URL_SCHEMES.include?(url.scheme)

      @url = url
      @body = body
      @headers = headers
    end

    def build
      raise NoArticlesFound if articles.empty?

      Reducer.call(articles, url:)
      Cleanup.call(articles, url:, keep_different_domain: true)

      channel.articles = articles

      Html2rss::AutoSource::RssBuilder.new(
        channel:,
        articles:
      ).call
    end

    def articles
      @articles ||= Scraper.from(parsed_body).flat_map do |scraper|
        instance = scraper.new(parsed_body, url:)

        articles_in_thread = Parallel.map(instance.each) do |article_hash|
          Log.debug "Scraper: #{scraper} in worker: #{Parallel.worker_number} [#{article_hash[:url]}]"

          Article.new(**article_hash, scraper:)
        end

        Reducer.call(articles_in_thread, url:)

        articles_in_thread
      end
    end

    def channel
      @channel ||= Channel.new(parsed_body, headers: @headers, url:)
    end

    private

    attr_reader :url

    # @return [Nokogiri::HTML::Document]
    def parsed_body
      @parsed_body ||= Nokogiri.HTML(@body)
                               .tap do |doc|
        # Remove comments from the document
        doc.xpath('//comment()').each(&:remove)
      end.freeze
    end
  end
end
