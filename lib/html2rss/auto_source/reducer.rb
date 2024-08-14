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

          articles.filter!(&:valid?)

          Log.debug "Reducer: having longest #{articles.size} articles"

          articles = keep_longest_attributes(articles, keep: [:generated_by]) { |article| article.url.path }

          Log.debug "Reducer: end with #{articles.size} valid articles"

          articles
        end

        private

        # @param articles [Array<Article>]
        # @param block [Proc] returns a key to group the articles for further processing
        # @return [Array<Article>] reduced articles
        def keep_longest_attributes(articles, keep:, &)
          grouped_by_block = articles.group_by(&)
          grouped_by_block.each_with_object([]) do |(_key, grouped_articles), result|
            result << find_longest_attributes_article(grouped_articles, keep:)
          end
        end

        def find_longest_attributes_article(articles, keep:)
          longest_attributes_article = {}
          articles.each do |article|
            keep_longest_attributes_from_article(longest_attributes_article, article, keep:)
          end

          Article.new(**longest_attributes_article)
        end

        def keep_longest_attributes_from_article(longest_attributes_article, article, keep:)
          article.each do |key, value|
            if keep.include?(key)
              longest_attributes_article[key] ||= []
              longest_attributes_article[key] << value
            elsif value && value.to_s.size > longest_attributes_article[key].to_s.size
              longest_attributes_article[key] = value
            end
          end
        end
      end
    end
  end
end
