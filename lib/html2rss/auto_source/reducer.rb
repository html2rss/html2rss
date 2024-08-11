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

          articles = keep_longest_attributes(articles)

          Log.debug "Reducer: having longest #{articles.size} articles"

          articles.filter!(&:valid?)

          Log.debug "Reducer: end with #{articles.size} valid articles"

          articles
        end

        private

        def keep_longest_attributes(articles)
          grouped_by_url = articles.group_by { |article| article.url.to_s.split('#').first }
          grouped_by_url.each_with_object([]) do |(_url, articles_with_same_url), result|
            result << find_longest_attributes_article(articles_with_same_url)
          end
        end

        def find_longest_attributes_article(articles)
          longest_attributes_article = {}
          articles.each do |article|
            keep_longest_attributes_from_article(longest_attributes_article, article)
          end

          Article.new(**longest_attributes_article)
        end

        def keep_longest_attributes_from_article(longest_attributes_article, article)
          article.each do |key, value|
            if value && value.to_s.size > longest_attributes_article[key].to_s.size
              longest_attributes_article[key] = value
            end
          end
        end
      end
    end
  end
end
