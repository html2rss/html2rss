# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # The Scraper module contains all scrapers that can be used to extract articles.
    # Each scraper should implement a `call` method that returns an array of article hashes.
    # Each scraper should also implement an `articles?` method that returns true if the scraper
    # can potentially be used to extract articles from the given HTML.
    #
    module Scraper
      SCRAPERS = [
        Html,
        Schema,
        SemanticHtml
      ].freeze

      ##
      # Error raised when no suitable scraper is found.
      class NoScraperFound < Html2rss::Error; end

      ##
      # Returns an array of scrapers that claim to find articles in the parsed body.
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML body.
      # @return [Array<Class>] An array of scraper classes that can handle the parsed body.
      def self.from(parsed_body)
        scrapers = SCRAPERS.select { |scraper| scraper.articles?(parsed_body) }
        raise NoScraperFound, 'No suitable scraper found for URL.' if scrapers.empty?

        scrapers
      end
    end
  end
end
