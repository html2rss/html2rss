# frozen_string_literal: true

module Html2rss
  module Extraction
    Result = Data.define(:status, :articles, :error_kind)

    ##
    # One extraction run as plain data: strings, numbers, symbols, arrays and hashes only.
    #
    # status: +:ok+ (at least one article), +:empty+ (the page yielded none) or +:error+.
    # articles: one hash per article with +:url+, +:title+, +:description+, +:image+, +:author+, +:guid+,
    # +:published_at+ (ISO 8601), +:categories+, +:enclosures+, +:media+ and +:scraper+ (the scraper that matched it).
    # error_kind: the {Html2rss::ErrorKind} of the failure, nil unless +:error+.
    class Result
      ##
      # @param articles [Array<Html2rss::Article>]
      # @return [Result]
      def self.ok(articles)
        new(status: articles.empty? ? :empty : :ok, articles: articles.map { plain(_1) }, error_kind: nil)
      end

      ##
      # @param error [Html2rss::Error]
      # @return [Result]
      def self.failure(error)
        new(status: :error, articles: [], error_kind: ErrorKind[error.kind])
      end

      ##
      # @param article [Html2rss::Article]
      # @return [Hash{Symbol => Object}]
      def self.plain(article)
        { url: article.url&.to_s, title: article.title, description: article.description, image: article.image&.to_s,
          author: article.author, guid: article.guid, published_at: article.published_at&.iso8601,
          categories: article.categories, media: article.media?,
          scraper: AutoSource::Scraper.name_for(article.scraper),
          enclosures: plain_enclosures(article) }
      end
      private_class_method :plain

      ##
      # @param article [Html2rss::Article]
      # @return [Array<Hash{Symbol => Object}>] the article's enclosures as plain data
      def self.plain_enclosures(article)
        article.enclosures.map do |file|
          { url: file.url.to_s, type: file.type, bytes_length: file.bytes_length, duration: file.duration }
        end
      end
      private_class_method :plain_enclosures
    end
  end
end
