# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # :reek:MissingSafeMethod { enabled: false }
    # It applies various strategies to filter and refine the article list.
    class Cleanup
      DEFAULT_CONFIG = {
        keep_different_domain: false,
        min_words_title: 3
      }.freeze

      VALID_SCHEMES = %w[http https].freeze

      class << self
        def call(articles, url:, keep_different_domain:, min_words_title:)
          log_cleanup_start(articles)

          apply_cleanup_filters(articles, url, keep_different_domain, min_words_title)

          log_cleanup_end(articles)
          articles
        end

        ##
        # Deduplicates articles by a given key.
        #
        # @param articles [Array<Article>] The list of articles to process.
        # @param key [Symbol] The key to deduplicate by.
        def deduplicate_by!(articles, key)
          seen = {}
          articles.reject! do |article|
            value = article.public_send(key)
            value.nil? || seen.key?(value).tap { seen[value] = true }
          end
        end

        ##
        # Keeps only articles with HTTP or HTTPS URLs.
        #
        # @param articles [Array<Article>] The list of articles to process.
        def keep_only_http_urls!(articles)
          articles.select! { |article| VALID_SCHEMES.include?(article.url&.scheme) }
        end

        ##
        # Rejects articles that have a URL not on the same domain as the source.
        #
        # @param articles [Array<Article>] The list of articles to process.
        # @param base_url [Html2rss::Url] The source URL to compare against.
        def reject_different_domain!(articles, base_url)
          base_host = base_url.host
          articles.select! { |article| article.url&.host == base_host }
        end

        ##
        # Keeps only articles with a title that is present and has at least `min_words_title` words.
        #
        # @param articles [Array<Article>] The list of articles to process.
        # @param min_words_title [Integer] The minimum number of words in the title.
        def keep_only_with_min_words_title!(articles, min_words_title:)
          articles.select! do |article|
            title = article.title
            title ? word_count_at_least?(title, min_words_title) : true
          end
        end

        private

        def log_cleanup_start(articles)
          initial_size = articles.size
          Log.debug "Cleanup: start with #{initial_size} articles"
        end

        def apply_cleanup_filters(articles, url, keep_different_domain, min_words_title)
          filter_valid_articles(articles)
          deduplicate_articles(articles)
          filter_urls_and_domains(articles, url, keep_different_domain)
          filter_by_title_length(articles, min_words_title)
        end

        def log_cleanup_end(articles)
          final_size = articles.size
          Log.debug "Cleanup: end with #{final_size} articles"
        end

        def filter_valid_articles(articles)
          articles.select!(&:valid?)
        end

        def deduplicate_articles(articles)
          deduplicate_by!(articles, :url)
        end

        def filter_urls_and_domains(articles, url, keep_different_domain)
          keep_only_http_urls!(articles)
          reject_different_domain!(articles, url) unless keep_different_domain
        end

        def filter_by_title_length(articles, min_words_title)
          keep_only_with_min_words_title!(articles, min_words_title:)
        end

        def word_count_at_least?(str, min_words)
          count = 0
          str.to_s.scan(/\b\w+\b/) do
            count += 1
            return true if count >= min_words
          end
          false
        end
      end
    end
  end
end
