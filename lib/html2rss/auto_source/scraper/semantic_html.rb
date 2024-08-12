# frozen_string_literal: true

require 'addressable'
require 'parallel'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scraps articles by looking for common markup tags (article, section, li)
      # containing an <a href> tag.
      #
      # See:
      # 1. https://developer.mozilla.org/en-US/docs/Web/HTML/Element/article
      class SemanticHtml
        ##
        ## key = parent element name to find, when searching for articles,
        # value = array of CSS selectors selecting <a href>
        #
        # Note: X :not(x) a[href] is used to avoid selecting <X><X><a href></X></X>
        ANCHOR_TAG_SELECTORS = {
          'section' => ['section :not(section) a[href]'],
          'tr' => ['table tr :not(tr) a[href]'],
          'div' => ['div :not(div) a[href]'],
          'article' => [
            'article :not(article) a[href]',
            'article a[href]'
          ],
          'li' => [
            'ul > li :not(li) a[href]',
            'ol > li :not(li) a[href]'
          ]
        }.freeze

        ARTICLE_TAGS = ANCHOR_TAG_SELECTORS.keys

        HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze

        # TODO: also handle <h2><a href>...</a></h2> as article
        # TODO: also handle <X class="article"><a href>...</a></X> as article

        def self.articles?(parsed_body)
          ANCHOR_TAG_SELECTORS.each_value do |selectors|
            selectors.each { |selector| return true if parsed_body.css(selector).any? }
          end
          false
        end

        def self.find_tag_in_ancestors(current_tag, tag_name, stop_tag: 'html')
          return current_tag if current_tag.name == tag_name

          stop_tags = Set[tag_name, stop_tag]

          while current_tag.respond_to?(:parent) && !stop_tags.member?(current_tag.name)
            current_tag = current_tag.parent
          end

          current_tag
        end

        def self.find_closest_selector(current_tag, selector: 'a[href]:not([href=""])')
          current_tag.css(selector).first || find_closest_selector_upwards(current_tag, selector:)
        end

        def self.find_closest_selector_upwards(current_tag, selector:)
          while current_tag
            found = current_tag.at_css(selector)
            return found if found

            return nil unless current_tag.respond_to?(:parent)

            current_tag = current_tag.parent
          end
        end

        # Returns an array of [tag_name, selector] pairs
        # @return [Array<[<String>, <String>]>]
        def self.anchor_tag_selector_pairs
          ANCHOR_TAG_SELECTORS.flat_map do |tag_name, selectors|
            selectors.map { |selector| [tag_name, selector] }
          end
        end

        def initialize(parsed_body, url:)
          @parsed_body = parsed_body
          @url = url
        end

        attr_reader :parsed_body

        ##
        # @return [Array<Hash>] The scraped articles.
        def each(&)
          SemanticHtml.anchor_tag_selector_pairs.each do |tag_name, selector|
            parsed_body.css(selector)
                       .each do |selected_tag|
              article_tag = SemanticHtml.find_tag_in_ancestors(selected_tag, tag_name)

              article_hash = ArticleExtractor.new(article_tag, url: @url).scrape

              yield article_hash if article_hash
            end
          end
        end
      end
    end
  end
end
