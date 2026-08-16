# frozen_string_literal: true

require 'json'

module Html2rss
  class AutoSource
    module Scraper
      # Extracts articles from JSON XHR/fetch responses captured during a
      # browser-tier scrape (see RequestService::Response#captured_responses).
      class XhrArticles
        include Enumerable

        # @return [Symbol] scraper config key
        def self.options_key = :xhr_articles

        # @param _opts [Hash] unused scraper options
        # @return [Integer] zero — no additional HTTP requests
        def self.request_slots(_opts = {}) = 0

        # Not detectable from HTML alone; instance {#extractable?} uses captures.
        #
        # @param _parsed_body [Nokogiri::HTML::Document, nil]
        # @return [Boolean]
        def self.articles?(_parsed_body) = false

        # @param _parsed_body [Nokogiri::HTML::Document, nil] unused HTML document
        # @param url [String, Html2rss::Url] page URL used to resolve relative links
        # @param captured_responses [Array<Hash>] JSON bodies from Response#captured_responses
        # @param _opts [Hash] scraper-specific options
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        def initialize(_parsed_body, url:, captured_responses: [], **_opts)
          @url = url
          @captured_responses = captured_responses
        end

        # @return [Boolean] true when any captured body contains article-like arrays
        def extractable?
          parsed_bodies.any? { |doc| JsonState::CandidateDetector.candidate_array?(doc) }
        end

        # @yield [Hash{Symbol => Object}] normalized article hash
        # @return [Enumerator, void] article enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?

          parsed_bodies.each do |doc|
            JsonState.discover_articles(doc, base_url: @url) { |article| yield article if article }
          end
        end

        private

        def parsed_bodies
          @parsed_bodies ||= @captured_responses.filter_map { |captured| parse(captured) }
                                                .select { |doc| JsonState::CandidateDetector.candidate_array?(doc) }
        end

        def parse(captured)
          body = captured[:body] || captured['body']
          return unless body.is_a?(String)

          JSON.parse(body, symbolize_names: true)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
