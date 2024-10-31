# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # :reek:MissingSafeMethod { enabled: false }
    # It applies various strategies to filter and refine the article list.
    class Cleanup
      class << self
        def call(articles, url:, keep_different_domain: false)
          Log.debug "Cleanup: start with #{articles.size} articles"

          articles.select!(&:valid?)

          remove_short!(articles, :title)

          deduplicate_by!(articles, :url)
          deduplicate_by!(articles, :title)

          keep_only_http_urls!(articles)
          reject_different_domain!(articles, url) unless keep_different_domain

          remove_title_in_description!(articles)

          Log.debug "Cleanup: end with #{articles.size} articles"
          articles
        end

        private

        ##
        # Removes articles with short values for a given key.
        #
        # @param articles [Array<Article>] The list of articles to process.
        # @param key [Symbol] The key to check for short values.
        # @param min_words [Integer] The minimum number of words required.
        def remove_short!(articles, key = :title, min_words: 2)
          articles.reject! do |article|
            value = article.public_send(key)
            value.nil? || value.to_s.split.size < min_words
          end
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
          articles.select! { |article| %w[http https].include?(article.url&.scheme) }
        end

        ##
        # Rejects articles that have a URL not on the same domain as the source.
        #
        # @param articles [Array<Article>] The list of articles to process.
        # @param base_url [Addressable::URI] The source URL to compare against.
        def reject_different_domain!(articles, base_url)
          base_host = base_url.host
          articles.select! { |article| article.url&.host == base_host }
        end

        ##
        # Removes the title from the description if it's either at the beginning
        # or within the first 50% of the description.
        #
        # @param articles [Array<Article>] The list of articles to process.
        def remove_title_in_description!(articles)
          articles.each do |article|
            max_range = (article.description.size * 0.5).to_i
            next unless article.description.index(article.title).to_i < max_range

            article.description = article.description.gsub(/^(.{0,#{max_range}})#{Regexp.escape(article.title)}/,
                                                           '\1').strip
          end
        end
      end
    end
  end
end
