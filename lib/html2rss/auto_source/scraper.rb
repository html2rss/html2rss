# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Scraper module contains all scrapers that can be used to extract articles.
    # Each scraper should implement a `call` method that returns an array of article hashes.
    # Each scraper should also implement a `articles?` method that returns true if the scraper
    # can potentially be used to extract articles from the given HTML.
    #
    module Scraper
      SCRAPERS = [
        JsonLd,
        SemanticHtml
      ].freeze

      ##
      # Error raised when no suitable scraper is found.
      class NoScraperFound < Html2rss::Error; end

      def self.scrapers(parsed_body)
        SCRAPERS.select { |scraper| scraper.articles?(parsed_body) }
                .tap do |scrapers|
          raise NoScraperFound, 'No suitable scraper found for URL.' if scrapers.empty?
        end
      end
    end
  end
end
