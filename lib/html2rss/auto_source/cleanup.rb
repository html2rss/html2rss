# frozen_string_literal: true

require 'byebug'

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
        # # TODO: extract to separate "merger" / reducer classes
        #
        # @param articles [Array<Hash>]
        # @return [Array<Hash>]
        def keep_longest_attributes(articles)
          articles.group_by { |article| article[:url] }
                  .map do |_url, articles_with_same_url|
            longest_attributes_article = articles_with_same_url.max_by do |article|
              article.transform_values { |value| value.to_s.size }
            end

            longest_attributes_article
          end
        end

        def remove_short!(articles, key = :title, min_words: 3)
          articles.reject! do |article|
            size = article[key]&.to_s&.split&.size.to_i
            size < min_words
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
