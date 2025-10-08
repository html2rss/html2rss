# frozen_string_literal: true

require 'set' # rubocop:disable Lint/RedundantRequireStatement

module Html2rss
  module Articles
    ##
    # Deduplicates a list of articles while preserving their original order.
    #
    # The deduplicator prefers each article's URL (combined with its ID when
    # available) to determine uniqueness. When no URL is present, it falls
    # back to the article ID, then to the GUID enriched with title and
    # description metadata. If none of these identifiers are available it
    # defaults to the article object's hash to preserve the original entry.
    class Deduplicator
      ##
      # @param articles [Array<Html2rss::RssBuilder::Article>, nil]
      def initialize(articles = nil)
        @articles = articles
      end

      ##
      # Returns the list of unique articles, preserving the order of the
      # original collection and keeping the first occurrence of a duplicate.
      #
      # @param articles [Array<Html2rss::RssBuilder::Article>]
      # @return [Array<Html2rss::RssBuilder::Article>]
      def call(articles = nil)
        collection = articles || @articles
        raise ArgumentError, 'articles must be provided' unless collection

        deduplicate(collection)
      end

      private

      attr_reader :articles

      def deduplicate(collection)
        seen = Set.new

        collection.each_with_object([]) do |article, deduplicated|
          fingerprint = deduplication_fingerprint_for(article)
          fingerprint ||= article.hash
          next unless seen.add?(fingerprint)

          deduplicated << article
        end
      end

      def deduplication_fingerprint_for(article)
        return unless article.respond_to?(:deduplication_fingerprint)

        article.deduplication_fingerprint
      end
    end
  end
end
