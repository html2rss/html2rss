# frozen_string_literal: true

module Html2rss
  class ArticlePipeline
    module Processors
      ##
      # Removes duplicate articles while preserving the original order.
      class Deduplicator
        ##
        # @param articles [Array<Html2rss::Article>]
        # @return [Array<Html2rss::Article>]
        def call(articles)
          seen_keys = {}

          articles.each_with_object([]) do |article, unique|
            key = deduplication_key(article)

            next if key && seen_keys[key]

            seen_keys[key] = true if key
            unique << article
          end
        end

        private

        def deduplication_key(article)
          [article.url&.to_s, article.id, article.title].find do |candidate|
            next if candidate.nil?

            candidate.respond_to?(:empty?) ? !candidate.empty? : true
          end
        end
      end
    end
  end
end
