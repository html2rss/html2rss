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
        ANCHOR_TAG_SELECTORS = {
          'section' => ['section :not(section) a[href]'],
          'tr' => ['table tr :not(tr) a[href]'],
          'article' => [
            'article :not(article) a[href]',
            'article a[href]'
          ],
          'li' => [
            'ul > li :not(li) a[href]',
            'ol > li :not(li) a[href]'
          ]
        }.freeze

        def self.options_key = :semantic_html

        # Check if the parsed_body contains articles
        # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document
        # @return [Boolean] True if articles are found, otherwise false.
        def self.articles?(parsed_body)
          return false unless parsed_body

          ANCHOR_TAG_SELECTORS.each_value do |selectors|
            return true if selectors.any? { |selector| parsed_body.at_css(selector) }
          end

          false
        end

        # Returns an array of [tag_name, selector] pairs
        # @return [Array<[String, String]>] Array of tag name and selector pairs
        def self.anchor_tag_selector_pairs
          ANCHOR_TAG_SELECTORS.flat_map do |tag_name, selectors|
            selectors.map { |selector| [tag_name, selector] }
          end
        end

        def initialize(parsed_body, url:, **opts)
          @parsed_body = parsed_body
          @url = url
          @opts = opts
        end

        attr_reader :parsed_body

        ##
        # @yieldparam [Hash] The scraped article hash
        # @return [Enumerator] Enumerator for the scraped articles
        def each
          return enum_for(:each) unless block_given?

          SemanticHtml.anchor_tag_selector_pairs.each do |tag_name, selector|
            parsed_body.css(selector).each do |selected_tag|
              article_tag = HtmlNavigator.find_tag_in_ancestors(selected_tag, tag_name)

              if article_tag && (article_hash = HtmlExtractor.new(article_tag, base_url: @url).call)
                yield article_hash
              end
            end
          end
        end
      end
    end
  end
end
