# frozen_string_literal: true

module Html2rss
  module Test
    ##
    # Builds the bounded +items+ preview of a test run from extracted articles,
    # independent of the quality gate and of the rendered RSS.
    module ItemSample
      # Maximum characters kept in an item's plain-text description.
      DESCRIPTION_LIMIT = 200

      ##
      # @param articles [Array<Html2rss::Article>] extracted articles
      # @param limit [Integer] maximum number of items, >= 0
      # @return [Array<Hash{Symbol => Object}>]
      def self.call(articles, limit:)
        articles.first(limit).map { |article| item_for(article) }
      end

      ##
      # @param article [Html2rss::Article]
      # @return [Hash{Symbol => Object}]
      def self.item_for(article)
        {
          title: article.title.to_s.strip,
          url: article.url&.to_s,
          published_at: article.published_at&.iso8601,
          description: plain_description(article.description),
          image: article.image&.to_s,
          categories: article.categories
        }
      end

      ##
      # @param html [String, nil]
      # @return [String] whitespace-collapsed text truncated to {DESCRIPTION_LIMIT} characters
      def self.plain_description(html)
        text = Nokogiri::HTML.fragment(html).text.gsub(/\s+/, ' ').strip
        text[0, DESCRIPTION_LIMIT]
      end
    end
  end
end
