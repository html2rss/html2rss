# frozen_string_literal: true

require 'set'

module Html2rss
  class ArticlePipeline
    module Processors
      ##
      # Deduplicates a list of articles while preserving their original order.
      #
      # The processor prefers each article's URL (combined with its ID when
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

          seen = Set.new

          collection.each_with_object([]) do |article, deduplicated|
            fingerprint = fingerprint_for(article)
            next if seen.include?(fingerprint)

            seen.add(fingerprint)
            deduplicated << article
          end
        end

        private

        attr_reader :articles

        def fingerprint_for(article)
          if article.respond_to?(:url) && (url = article.url)
            components = [url.to_s]
            components << article.id if article.respond_to?(:id) && article.id

            return components.join('#!/')
          end

          return article.id if article.respond_to?(:id) && article.id

          if article.respond_to?(:guid) && article.guid
            parts = [article.guid]
            parts << article.title if article.respond_to?(:title) && article.title
            parts << article.description if article.respond_to?(:description) && article.description

            return parts.compact.join('#!/')
          end

          article.hash
        end
      end
    end
  end
end
