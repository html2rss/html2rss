# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      # Extracts the earliest date from an article_tag.
      class DateExtractor
        # @param article_tag [Nokogiri::XML::Element] article container node
        # @param leftover_lines [Array<String>] leftover visible lines (already split)
        # @param time_zone [String] channel time zone for naive values
        # @return [DateTime, nil]
        def self.call(article_tag, leftover_lines: [], time_zone: 'UTC')
          datetimes = article_tag.respond_to?(:css) ? article_tag.css('[datetime]').map { |tag| tag['datetime'] } : []
          ArticleRules::Date.earliest(datetimes, leftover_lines:, time_zone:)
        end
      end
    end
  end
end
