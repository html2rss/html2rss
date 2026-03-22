# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # The Scraper module contains all scrapers that can be used to extract articles.
    # Each scraper should implement an `each` method that yields article hashes.
    # Each scraper should also implement an `articles?` method that returns true if the scraper
    # can potentially be used to extract articles from the given HTML.
    #
    # Detection is intentionally shallow for most scrapers, but instance-based
    # matching is available for scrapers that need to carry expensive selection
    # state forward into extraction.
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
      # Returns an array of scraper classes that claim to find articles in the parsed body.
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML body.
      # @param opts [Hash] The options hash.
      # @return [Array<Class>] An array of scraper classes that can handle the parsed body.
      def self.from(parsed_body, opts = Html2rss::AutoSource::DEFAULT_CONFIG[:scraper])
        scrapers = SCRAPERS.select { |scraper| opts.dig(scraper.options_key, :enabled) }
        scrapers.select! { |scraper| scraper.articles?(parsed_body) }

        raise NoScraperFound, 'No scrapers found for URL.' if scrapers.empty?

        scrapers
      end

      # Returns scraper instances ready for extraction.
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML body.
      # @param url [String, Html2rss::Url] The page url.
      # @param request_session [Html2rss::RequestSession, nil] Shared follow-up session.
      # @param opts [Hash] The options hash.
      # @return [Array<Object>] An array of scraper instances that can handle the parsed body.
      #
      # `instances_for` is the main entrypoint for extraction. It lets a scraper
      # decide whether it matches using the same instance that will later yield
      # article hashes, which keeps precomputed state close to the scraper that
      # owns it.
      def self.instances_for(parsed_body, url:, request_session: nil,
                             opts: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper])
        instances = SCRAPERS.filter_map do |scraper|
          next unless opts.dig(scraper.options_key, :enabled)

          instance = scraper.new(parsed_body, url:, request_session:, **opts.fetch(scraper.options_key, {}))
          next unless extractable_instance?(instance, parsed_body)

          instance
        end

        raise NoScraperFound, 'No scrapers found for URL.' if instances.empty?

        instances
      end

      def self.extractable_instance?(instance, parsed_body)
        return instance.extractable? if instance.respond_to?(:extractable?)

        instance.class.articles?(parsed_body)
      end
      private_class_method :extractable_instance?
    end
  end
end
