# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # The contract every scraper shares: built from a parsed page and its URL, enumerates article hashes
      # via +each+, and answers +extractable?+ for an already built instance.
      #
      # Each subclass defines, explicitly and with no default here:
      # - +self.options_key+ (config key),
      # - +self.request_slots(opts = {})+ (follow-up requests it may spend; a default would hide a miscount),
      # - +self.articles?(parsed_body)+ (shallow detection), and
      # - +each+.
      #
      # The base calls only that public surface, never a subclass-private method.
      class Base
        include Enumerable

        # @param parsed_body [Nokogiri::HTML::Document, Hash, Array, nil] parsed page or JSON document
        # @param url [String, Html2rss::Url] page URL used to resolve relative links
        def initialize(parsed_body, url:)
          @parsed_body = parsed_body
          @url = url
        end

        # @return [Boolean] true when this instance's page holds extractable articles
        def extractable? = self.class.articles?(parsed_body)

        private

        attr_reader :parsed_body, :url
      end
    end
  end
end
