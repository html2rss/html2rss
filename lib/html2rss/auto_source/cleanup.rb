# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # It has several strategies.
    # :reek:MissingSafeMethod { enabled: false }
    class Cleanup
      class << self
        def call(articles, url:)
          Log.debug "Cleanup: start with #{articles.size} articles"

          articles.select!(&:valid?)

          remove_short!(articles, :title)

          deduplicate_by!(articles, :url)
          deduplicate_by!(articles, :title)

          keep_only_http_urls!(articles)
          reject_different_domain!(articles, url)

          Log.debug "Cleanup: end with #{articles.size} articles"
          articles
        end

        private

        ##
        # Removes articles with short values for a given key.
        #
        # @param articles [Array<Hash>] The list of articles to process.
        # @param key [Symbol] The key to check for short values.
        # @param min_words [Integer] The minimum number of words required.
        def remove_short!(articles, key = :title, min_words: 3)
          articles.reject! do |article|
            value = article.public_send(key)
            return true unless value

            size = value.to_s.size.to_i
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
            value = article.public_send(key)
            next true if !value || seen.key?(value)

            seen[value] = true
            false
          end
        end

        ##
        # Keeps only articles with HTTP or HTTPS URLs.
        #
        # @param articles [Array<Hash>] The list of articles to process.
        def keep_only_http_urls!(articles)
          articles.select! { |article| article.url.scheme.start_with?('http') }
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
      end
    end
  end
end