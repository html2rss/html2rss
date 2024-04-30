# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Channel
      ##
      # Extracts channel information from the HTML document's <head>.
      class Metadata
        ##
        # Initializes a new Metadata object.
        #
        # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
        # @param url [Addressable::URI] The URL of the HTML document.
        def initialize(parsed_body, url:)
          @url = url
          @parsed_body = parsed_body
        end

        ##
        # Extracts metadata from the HTML document.
        #
        # @return [Hash] A hash containing the URL, title, language, and description.
        def call
          {
            url: extract_url,
            title: extract_title,
            language: extract_language,
            description: extract_description
          }
        end

        private

        attr_reader :parsed_body

        def extract_url
          @url.normalize.to_s
        end

        def extract_title
          parsed_body.at_css('head > title')&.text
        end

        def extract_language
          return parsed_body['lang'] if parsed_body.name == 'html'

          parsed_body.at_css('html[lang]')&.[]('lang')
        end

        def extract_description
          parsed_body.at_css('meta[name="description"]')&.[]('content') || ''
        end
      end
    end
  end
end
