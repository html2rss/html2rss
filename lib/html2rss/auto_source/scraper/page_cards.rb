# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Shared plumbing of the heuristic page-card scrapers ({Html}, {SemanticHtml}): one memoized
      # SST document and link resolver per page, provided by AutoSource or built on demand.
      # Subclasses own segmenting, ranking, +each+ and +extractable?+.
      class PageCards < Base
        # Absolute base URL used when probe-time detection needs to normalize relative hrefs.
        DETECTION_BASE_URL = 'https://example.com'

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
        # @return [Boolean] true when a probe instance finds ranked segments
        def self.articles?(parsed_body)
          return false unless parsed_body

          new(parsed_body, url: DETECTION_BASE_URL).extractable?
        end

        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed HTML document
        # @param url [String, Html2rss::Url] page URL used to resolve relative links
        # @param document [SST::Document, nil] shared document built once per page
        # @param link_resolver [Scoring::LinkResolver, nil] shared link resolver
        def initialize(parsed_body = nil, url:, document: nil, link_resolver: nil)
          super(parsed_body, url:)
          @provided_document = document
          @provided_link_resolver = link_resolver
        end

        private

        def link_resolver
          @link_resolver ||= @provided_link_resolver || Scoring::LinkResolver.new(url)
        end

        def document
          @document ||= @provided_document || SST::Normalizer.call(parsed_body, vocabulary: link_resolver.vocabulary)
        end
      end
    end
  end
end
