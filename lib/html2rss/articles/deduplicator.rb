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
          fingerprint = fingerprint_for(article)
          next unless seen.add?(fingerprint)

          deduplicated << article
        end
      end

      def fingerprint_for(article)
        fingerprint_from_url(article) || fingerprint_from_id(article) || fingerprint_from_guid(article) || article.hash
      end

      def fingerprint_from_url(article)
        url = safe_property(article, :url)
        return unless url

        [url.to_s, safe_property(article, :id)].compact.join('#!/')
      end

      def fingerprint_from_id(article)
        safe_property(article, :id)
      end

      def fingerprint_from_guid(article)
        guid = safe_property(article, :guid)
        return unless guid

        [guid, safe_property(article, :title), safe_property(article, :description)].compact.join('#!/')
      end

      def safe_property(article, property)
        return unless article.respond_to?(property)

        article.public_send(property)
      end
    end
  end
end
