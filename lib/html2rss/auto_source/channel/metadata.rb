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
            title: parsed_body.css('head > title').first&.text,
            language: parsed_body.css('html').first.attr('lang'),
            description: parsed_body.css('meta[name="description"]')&.first&.[]('content')
          }
        end

        private

        attr_reader :parsed_body, :url
      end
    end
  end
end
