# frozen_string_literal: true

require 'byebug'

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # It has several strategies
    # :reek:MissingSafeMethod { enabled: false }
    class Cleanup
      class << self
        def call(articles, url:)
          # Log.debug "Clean Articels: start with #{articles.size} articles"

          keep_longest_attributes(articles)
          articles.filter!(&:valid?)

          remove_short!(articles, :title)

          deduplicate_by!(articles, :url)
          deduplicate_by!(articles, :title)
          remove_empty!(articles, :url)
          remove_empty!(articles, :title)
          keep_only_http_urls!(articles)
          reject_different_domain!(articles, url)

          articles
        end

        ##
        # Removes articles with short values for a given key.
        #
        # @param articles [Array<Hash>] The list of articles to process.
        # @param key [Symbol] The key to check for short values.
        # @param min_words [Integer] The minimum number of words required.
        def remove_short!(articles, key = :title, min_words: 3)
          articles.reject! do |article|
            return true unless article[key]

            size = article[key].to_s.size.to_i
            size < min_words
          end
        end

        ##
        # Deduplicates articles by a given key.
        #
        # @param articles [Array<Hash>] The list of articles to process.
        # @param key [Symbol] The key to deduplicate by.
        def deduplicate_by!(articles, key)
          seen = {}
          articles.reject! do |article|
            value = article[key]&.to_s&.strip
            next true if value.nil? || seen[value]

            seen[value] = true
            false
          end
        end

        ##
        # Removes articles with empty values for a given key.
        #
        # @param articles [Array<Hash>] The list of articles to process.
        # @param key [Symbol] The key to check for empty values.
        def remove_empty!(articles, key)
          articles.reject! { |article| article[key].to_s.strip.empty? }
        end

        ##
        # Keeps only articles with HTTP or HTTPS URLs.
        #
        # @param articles [Array<Hash>] The list of articles to process.
        def keep_only_http_urls!(articles)
          articles.select! { |article| article[:url].scheme.start_with?('http') }
        end

        ##
        # Rejects articles which have a URL that is not on the same domain as the source.
        #
        # @param articles [Array<Article>] The list of articles to process.
        # @param base_url [String] The source URL to compare against.
        def reject_different_domain!(articles, base_url)
          base_host = base_url.host

          articles.reject! do |article|
            article_url = article.url
            next true unless article_url

            article_url.host != base_host
          end
        end

        # TODO: extract to separate "merger" classes
        def keep_longest_attributes(articles)
          grouped_by_url = articles.group_by { |article| article[:url] }
          grouped_by_url.each_with_object([]) do |(_url, articles_with_same_url), result|
            result << find_longest_attributes_article(articles_with_same_url)
          end
        end

        private

        def find_longest_attributes_article(articles)
          longest_attributes_article = articles.shift
          articles.each do |article|
            keep_longest_attributes_from_article(longest_attributes_article, article)
          end
          longest_attributes_article
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
