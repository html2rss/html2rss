# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Extracts articles by looking for <script type="application/ld+json"> tag.
    #
    # See:
    # 1. https://schema.org/NewsArticle
    # 2. https://developers.google.com/search/docs/appearance/structured-data/article#microdata
    class JsonLd
      TAG_SELECTOR = 'script[type="application/ld+json"]'

      ARTICLE_TYPES = %w[Article NewsArticle].freeze

      def self.articles?(parsed_body)
        parsed_body.css(TAG_SELECTOR).any? { |script| supported_type?(script.text) }
      end

      def self.supported_type?(string)
        return false unless string.include?('@type')

        ARTICLE_TYPES.any? { |type| string.include?(type) }
      end

      def self.article_objects(object) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        # TODO: rewrite in an efficient way

        array = if object.is_a?(Hash)
                  if object.key?(:@type) && ARTICLE_TYPES.include?(object[:@type])
                    [object]
                  else
                    object.flat_map { |_, v| article_objects(v) }
                  end
                elsif object.is_a?(Array)
                  object.flat_map { |v| article_objects(v) }
                else
                  []
                end

        array.compact! if array.any?
        array
      end

      ##
      # Selects the extractor class based on article @type and returns the extracted article.
      #
      # @param article [Hash<Symbol, Object>]
      # @return [Base, nil] nil when the article type is not supported
      def self.extract(article)
        klass = case article[:@type]
                when 'Article'
                  Base
                when 'NewsArticle'
                  NewsArticle
                end

        return nil unless klass # TODO: probably worth a debug log?

        klass.to_article(article)
      end

      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      ##
      # @return [Array<Hash>] the extracted articles
      def call
        self.class.article_objects(parsed_json)
            .filter_map { |article| self.class.extract(article) }
      end

      def parsed_json
        scripts = parsed_body.css(TAG_SELECTOR)

        scripts.flat_map do |script|
          JSON.parse(script.text, symbolize_names: true) if self.class.supported_type?(script.text)
        end
      end

      private

      attr_reader :parsed_body
    end
  end
end
