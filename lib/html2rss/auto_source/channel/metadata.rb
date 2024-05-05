# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Channel
      ##
      # Extracts channel information from the HTML document's <head>.
      class Metadata
        def initialize(parsed_body, url:)
          @url = url
          @parsed_body = parsed_body
        end

        def call
          {
            url:,
            title: parsed_body.css('head > title')&.first&.text,
            language:,
            description: parsed_body.css('meta[name="description"]')&.first&.[]('content')
          }
        end

        private

        def language
          return parsed_body['lang'] if parsed_body.name == 'html'

          parsed_body.css('html[lang]')&.first&.[]('lang')
        end

        attr_reader :parsed_body, :url
      end
    end
  end
end
