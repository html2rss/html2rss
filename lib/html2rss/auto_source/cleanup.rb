# frozen_string_literal: true

require 'byebug'

module Html2rss
  class AutoSource
    ##
    # Cleanup is responsible for cleaning up the extracted articles.
    # It has several strategies
    class Cleanup
      class << self
        def clean_articles(articles) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
          Log.debug "Clean Articels: start with #{articles.size} articles"
          # TODO: extract to separate "merger" classes
          articles = keep_longest_attributes(articles)

          remove_short!(articles, :title)

          Log.debug "Clean Articels: within 1 with #{articles.size} articles"

          deduplicate_by!(articles, :url)

          Log.debug "Clean Articels: within 2 with #{articles.size} articles"

          deduplicate_by!(articles, :title)

          Log.debug "Clean Articels: within 3 with #{articles.size} articles"

          remove_empty!(articles, :url)

          Log.debug "Clean Articels: within 4 with #{articles.size} articles"
          remove_empty!(articles, :title)

          Log.debug "Clean Articels: within 5 with #{articles.size} articles"

          keep_only_http_urls!(articles)

          Log.debug "Clean Articels: end with #{articles.size} articles"
          articles
        end

        # TODO: reject articles which have a url that is not on the same domain as the source

        ##
        # With multiple articles sharing the same URL, build one out of them, by
        # keeping the longest attribute values.
        # # TODO: extract to separate "merger" / reducer classes
        #
        # @param articles [Article]
        # @return [Array<Arrticle>]
        def keep_longest_attributes(articles) # rubocop:disable Metrics/MethodLength
          grouped_by_url = articles.group_by { |article| article[:url] }

          grouped_by_url.each_pair.map do |_url, articles_with_same_url|
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
