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
          id = normalize(article.id)
          return id if id

          url = normalize(article.url&.to_s)
          return url if url

          normalize(article.title)
        end

        def normalize(value)
          return if value.nil?

          string = value.respond_to?(:strip) ? value.strip : value.to_s
          return if string.empty?

          string
        end
      end
    end
  end
end
