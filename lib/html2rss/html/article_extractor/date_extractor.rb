# frozen_string_literal: true

module Html2rss
  module Html
    class ArticleExtractor
      # Extracts the earliest date from an article_tag.
      class DateExtractor
        # @param article_tag [Nokogiri::XML::Element] article container node
        # @param leftover_lines [Array<String>] leftover visible lines (already split)
        # @param time_zone [String] channel time zone for naive values
        # @param vocabulary [Vocabulary::Scope] the page language's scope
        # @return [DateTime, nil]
        def self.call(article_tag, vocabulary:, time_zone:, leftover_lines: [])
          datetimes = article_tag.css('[datetime]').map { |tag| tag['datetime'] }
          ArticleRules::Date.earliest(datetimes, vocabulary:, leftover_lines:, time_zone:)
        end
      end
    end
  end
end
