# frozen_string_literal: true

require 'addressable'
require 'parallel'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes articles by looking for common markup tags (article, section, li)
      # containing an <a href> tag.
      #
      # See:
      # 1. https://developer.mozilla.org/en-US/docs/Web/HTML/Element/article
      class SemanticHtml
        include Enumerable

        ##
        # Map of parent element names to CSS selectors for finding <a href> tags.
        ANCHOR_TAG_SELECTORS = [
          ['article', 'article:not(:has(article)) a[href]'],
          ['section', 'section:not(:has(section)) a[href]'],
          ['li', 'li:not(:has(li)) a[href]'],
          ['tr', 'tr:not(:has(tr)) a[href]'],
          ['div', 'div:not(:has(div)) a[href]']
        ].freeze

        def self.options_key = :semantic_html

        # Check if the parsed_body contains articles
        # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document
        # @return [Boolean] True if articles are found, otherwise false.
        def self.articles?(parsed_body)
          return false unless parsed_body

          ANCHOR_TAG_SELECTORS.any? do |(_tag_name, selector)|
            parsed_body.at_css(selector)
          end
        end

        # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
        # @param url [String] The base URL.
        # @param extractor [Class] The extractor class to handle article extraction.
        # @param opts [Hash] Additional options.
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
          @opts = opts
        end

        attr_reader :parsed_body

        ##
        # Yields article hashes extracted from the HTML.
        # @yieldparam [Hash] The scraped article hash.
        # @return [Enumerator] Enumerator for the scraped articles.
        def each
          return enum_for(:each) unless block_given?

          each_candidate do |article_tag|
            if (article_hash = @extractor.new(article_tag, base_url: @url).call)
              yield article_hash
            end
          end
        end

        private

        # @yield [Nokogiri::XML::Element] Gives each found article tag.
        def each_candidate
          ANCHOR_TAG_SELECTORS.each do |tag_name, selector|
            parsed_body.css(selector).each do |anchor|
              next if anchor.path.match?(Html::TAGS_TO_IGNORE)

              # Traverse ancestors to find the parent tag matching tag_name
              article_tag = HtmlNavigator.find_tag_in_ancestors(anchor, tag_name)
              yield article_tag if article_tag
            end
          end
        end
      end
    end
  end
end
