# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Extracts articles by looking for NewsArticle microdata.
    #
    # See:
    # 1. https://schema.org/NewsArticle
    # 2. https://developers.google.com/search/docs/appearance/structured-data/article#microdata
    class NewsArticleMicrodata
      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      def self.articles?(parsed_body)
        parsed_body.css('[itemtype="https://schema.org/NewsArticle"]').any?
      end

      def call
        parsed_body.css('[itemtype="https://schema.org/NewsArticle"]').map do |article|
          {
            title: title(article),
            description: description(article),
            url: url(article),
            image: image(article),
            published_at: published_at(article),
            updated_at: updated_at(article)
          }
        end
      end

      private

      def title(article)
        article.css('[itemprop="headline"]')&.text
      end

      def description(article)
        article.css('[itemprop="description"]')&.text
      end

      def url(article)
        article.css('[itemprop="url"]').attr('href')&.value
      end

      def image(article)
        article.css('[itemprop="image"]').attr('src')&.value
      end

      def published_at(article)
        article.css('[itemprop="datePublished"]')&.text
      end

      def updated_at(article)
        article.css('[itemprop="dateModified"]')&.text
      end

      attr_reader :parsed_body
    end
  end
end
