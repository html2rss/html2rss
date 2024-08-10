# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # It has several strategies
    class Cleanup
      class << self
        def clean_articles(articles)
          # TODO: extract to separate "merger" classes
          articles = keep_longest_attributes(articles)

          remove_short!(articles, :title)

          deduplicate_by!(articles, :url)
          deduplicate_by!(articles, :title)

          remove_empty!(articles, :url)
          remove_empty!(articles, :title)

          keep_only_http_urls!(articles)

          articles
        end

        # TODO: reject articles which have a url that is not on the same domain as the source

        ##
        # With multiple articles sharing the same URL, build one out of them, by
        # keeping the longest attribute values.
        # # TODO: extract to separate "merger" classes
        def keep_longest_attributes(articles) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
          grouped_by_url = articles.group_by { |article| article[:url] }

          grouped_by_url = grouped_by_url.each_pair do |_url, articles_with_same_url|
            longest_attributes_article = articles_with_same_url.first

            articles_with_same_url.each do |article|
              article.each do |key, value|
                if value && value.size > longest_attributes_article[key].to_s.size
                  longest_attributes_article[key] = value
                end
              end
            end

            longest_attributes_article
          end

          values = grouped_by_url.values
          values.map!(&:first)
          values
        end

        def remove_short!(articles, key = :title, min_words: 2)
          articles.reject! do |article|
            size = article[key]&.to_s&.split&.size
            size.to_i < min_words
          end
        end

        def deduplicate_by!(articles, key)
          articles.uniq! { |article| article[key].to_s.strip }
        end

        def remove_empty!(articles, key)
          articles.reject! { |article| article[key].to_s.strip.empty? }
        end

        def keep_only_http_urls!(articles)
          articles.select! { |article| article[:url]&.to_s&.start_with?('http') }
        end
      end
    end
  end
end
