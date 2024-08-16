# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Reducer is responsible for reducing the list of articles.
    # It keeps only the longest attributes of articles with the same URL.
    # It also filters out invalid articles.
    class Reducer
      class << self
        def call(articles, **_options)
          Log.debug "Reducer: inited with #{articles.size} articles"

          reduce_by_keeping_longest_values(articles, keep: [:scraper]) { |article| article.url&.path }
        end

        private

        # @param articles [Array<Article>]
        # @return [Array<Article>] reduced articles
        def reduce_by_keeping_longest_values(articles, keep:, &)
          grouped_by_block = articles.group_by(&)
          grouped_by_block.each_with_object([]) do |(_key, grouped_articles), result|
            memo_object = {}
            grouped_articles.each do |article_hash|
              keep_longest_values(memo_object, article_hash, keep:)
            end

            result << Article.new(**memo_object)
          end
        end

        def keep_longest_values(memo_object, article_hash, keep:)
          article_hash.each do |key, value|
            next if value.eql?(memo_object[key])

            if keep.include?(key)
              memo_object[key] ||= []
              memo_object[key] << value
            elsif value && value.to_s.size > memo_object[key].to_s.size
              memo_object[key] = value
            end
          end
        end
      end
    end
  end
end
