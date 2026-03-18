# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # The Scraper module contains all scrapers that can be used to extract articles.
    # Each scraper should implement an `each` method that yields article hashes.
    # Each scraper should also implement an `articles?` method that returns true if the scraper
    # can potentially be used to extract articles from the given HTML.
    # Scrapers run in parallel threads, so implementations must avoid shared
    # mutable state and degrade by returning no articles when a follow-up would
    # be unsafe or unsupported.
    #
    module Scraper
      SCRAPERS = [
        WordpressApi,
        Schema,
        Microdata,
        JsonState,
        SemanticHtml,
        Html,
        RssFeedDetector
      ].freeze

      ##
      # Error raised when no suitable scraper is found.
      class NoScraperFound < Html2rss::Error; end

      ##
      # Returns an array of scrapers that claim to find articles in the parsed body.
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML body.
      # @param opts [Hash] The options hash.
      # @return [Array<Class>] An array of scraper classes that can handle the parsed body.
      def self.from(parsed_body, opts = Html2rss::AutoSource::DEFAULT_CONFIG[:scraper])
        scrapers = SCRAPERS.select { |scraper| opts.dig(scraper.options_key, :enabled) }
        scrapers.select! { |scraper| scraper.articles?(parsed_body) }

        raise NoScraperFound, 'No scrapers found for URL.' if scrapers.empty?

        scrapers
      end
    end
  end
end
