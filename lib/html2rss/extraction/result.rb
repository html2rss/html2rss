# frozen_string_literal: true

module Html2rss
  module Extraction
    Result = Data.define(:status, :articles, :scrapers, :error_kind)

    ##
    # One extraction run as plain data: strings, numbers, symbols, arrays and hashes only.
    #
    # status: +:ok+ (at least one article), +:empty+ (the page yielded none) or +:error+.
    # articles: one hash per article with +:url+, +:title+, +:description+, +:image+, +:author+, +:guid+,
    # +:published_at+ (ISO 8601), +:categories+, +:enclosures+, +:media+ and +:scraper+ (the scraper's name).
    # scrapers: scraper name => number of articles it produced, i.e. which scrapers matched.
    # error_kind: the {Html2rss::ErrorKind} of the failure, nil unless +:error+.
    class Result
      ##
      # @param articles [Array<Html2rss::Article>]
      # @return [Result]
      def self.ok(articles)
        new(status: articles.empty? ? :empty : :ok, articles: articles.map { plain(_1) },
            scrapers: articles.filter_map(&:scraper).tally.transform_keys { Status.scraper_name(_1) }, error_kind: nil)
      end

      ##
      # @param error [Html2rss::Error]
      # @return [Result]
      def self.failure(error)
        new(status: :error, articles: [], scrapers: {}, error_kind: ErrorKind[error.kind])
      end

      ##
      # @param article [Html2rss::Article]
      # @return [Hash{Symbol => Object}]
      def self.plain(article)
        { url: article.url&.to_s, title: article.title, description: article.description,
          image: article.image&.to_s, author: article.author, guid: article.guid,
          published_at: article.published_at&.iso8601, **plain_parts(article) }
      end
      private_class_method :plain

      ##
      # @param article [Html2rss::Article]
      # @return [Hash{Symbol => Object}] the collection-valued and flag fields of {.plain}
      def self.plain_parts(article)
        enclosures = article.enclosures.map do |enclosure|
          { url: enclosure.url.to_s, type: enclosure.type, bytes_length: enclosure.bytes_length,
            duration: enclosure.duration }
        end
        { categories: article.categories, enclosures:, media: article.media?,
          scraper: Status.scraper_name(article.scraper) }
      end
      private_class_method :plain_parts
    end
  end
end
