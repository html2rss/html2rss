# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Extracts articles by looking for <script type="application/ld+json"> tag.
      #
      # See:
      # 1. https://schema.org/NewsArticle
      # 2. https://developers.google.com/search/docs/appearance/structured-data/article#microdata
      class JsonLd
        TAG_SELECTOR = 'script[type="application/ld+json"]'
        ARTICLE_TYPES = %w[Article NewsArticle].freeze

        class << self
          def articles?(parsed_body)
            parsed_body.css(TAG_SELECTOR).any? { |script| article_type_supported?(script.text) }
          end

          def article_type_supported?(json_string)
            ARTICLE_TYPES.any? { |type| json_string.include?("\"@type\":\"#{type}\"") }
          end

          # :reek:DuplicateMethodCall
          def article_objects(object)
            case object
            in Hash if supported_article_type?(object)
              [object]
            in Hash
              object.values.flat_map { |item| article_objects(item) }.compact
            in Array
              object.flat_map { |item| article_objects(item) }.compact
            else
              []
            end
          end

          def scrape(article, url:)
            klass = scraper_for_type(article[:@type])
            klass&.to_article(article, url:)
          end

          def scraper_for_type(type)
            case type
            when 'Article' then Base
            when 'NewsArticle' then NewsArticle
            else
              Log.warn("JsonLD#scraper_for_type: Unsupported article type #{type}")
              nil
            end
          end

          def parse_json(json_string)
            JSON.parse(json_string, symbolize_names: true)
          rescue JSON::ParserError => error
            Log.warn("JsonLD#parsed_json: Failed to parse JSON: #{error.message}")
            nil
          end

          private

          def supported_article_type?(object)
            type = object[:@type]
            type && ARTICLE_TYPES.include?(type)
          end
        end

        def initialize(parsed_body, url:)
          @parsed_body = parsed_body
          @url = url
        end

        ##
        # @return [Array<Hash>] the scraped articles
        def call
          articles = JsonLd.article_objects(parsed_json)
          articles.map! { |article| JsonLd.scrape(article, url: @url) }
          articles
        end

        private

        def parsed_json
          @parsed_body.css(TAG_SELECTOR).filter_map do |script|
            script_text = script.text

            JsonLd.parse_json(script_text) if JsonLd.article_type_supported?(script_text)
          end
        end

        attr_reader :parsed_body, :url
      end
    end
  end
end
