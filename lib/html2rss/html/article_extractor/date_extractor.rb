# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      # Extracts the earliest date from an article_tag.
      class DateExtractor
        # @param article_tag [Nokogiri::XML::Element] article container node
        # @return [DateTime, nil]
        def self.call(article_tag)
          datetimes = article_tag.css('[datetime]').map { |tag| tag['datetime'] }
          ArticleRules::Date.earliest(datetimes)
        end
      end
    end
  end
end
