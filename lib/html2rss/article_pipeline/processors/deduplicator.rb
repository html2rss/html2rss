# frozen_string_literal: true

require 'set'

module Html2rss
  module ArticlePipeline
    module Processors
      ##
      # Deduplicates a list of articles while preserving their original order.
      #
      # The processor uses each article's guid when available to determine
      # uniqueness and falls back to a composite of id and URL. When neither is
      # present, it defaults to the article's hash so the original object is
      # retained.
      class Deduplicator
        ##
        # @param articles [Array<Html2rss::RssBuilder::Article>]
        def initialize(articles)
          @articles = Array(articles)
        end

        ##
        # Returns the list of unique articles, preserving the order of the
        # original collection and keeping the first occurrence of a duplicate.
        #
        # @return [Array<Html2rss::RssBuilder::Article>]
        def call
          seen = Set.new

          articles.each_with_object([]) do |article, deduplicated|
            fingerprint = fingerprint_for(article)
            next if seen.include?(fingerprint)

            seen.add(fingerprint)
            deduplicated << article
          end
        end

        private

        attr_reader :articles

        def fingerprint_for(article)
          return article.guid if article.respond_to?(:guid) && article.guid

          parts = []
          parts << article.id if article.respond_to?(:id) && article.id
          parts << article.url.to_s if article.respond_to?(:url) && article.url

          return parts.join('#!/') unless parts.empty?

          article.hash
        end
      end
    end
  end
end
