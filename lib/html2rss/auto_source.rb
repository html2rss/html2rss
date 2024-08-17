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

    def self.build_from_response(response, url)
      new(url, response:).build
    end

    def initialize(url, response: nil)
      unless url.is_a?(String) || url.is_a?(Addressable::URI)
        raise ArgumentError,
              'URL must be a String or Addressable::URI'
      end

      @url = Addressable::URI.parse(url)

      raise ArgumentError, 'URL must be absolute' unless @url.absolute?
      raise UnsupportedUrlScheme, "#{@url.scheme} not supported" unless SUPPORTED_URL_SCHEMES.include?(@url.scheme)

      @response = response if response
    end

    def build
      raise NoArticlesFound if articles.empty?

      Reducer.call(articles, url:)
      Cleanup.call(articles, url:, keep_different_domain: true)

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
      @parsed_body ||= Nokogiri.HTML(response.body)
                               .tap do |doc|
        # Remove comments from the document
        doc.xpath('//comment()').each(&:remove)
      end.freeze
    end
  end
end
