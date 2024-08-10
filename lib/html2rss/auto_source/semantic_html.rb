# frozen_string_literal: true

require 'addressable'
require 'parallel'

module Html2rss
  class AutoSource
    ##
    # Extracts articles by looking for <article> tags containing an <a href> tag.
    # An article is not considered an article without having an URL.
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
        # 'article' => ['article a[href]']
        # 'section' => ['section :not(section) a[href]'],
        # 'tr' => ['table tr a[href]'],
        # 'li' => ['li :not(li) a[href]'],
        # 'div' => ['div :not(div) a[href]'],
        'article' => ['article :not(article) a[href]'],
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

      def self.find_article_tag(anchor, tag_name)
        return anchor if anchor.name == tag_name

        article_tag = anchor.parent
        article_tag = article_tag.parent while article_tag && article_tag.name != tag_name
        article_tag
      end

      # Returns an array of [tag_name, selector] pairs
      # @return [Array<[<String>, <String>]>]
      def self.tag_and_selector
        @tag_and_selector ||= [].tap do |tag_and_selector|
          ANCHOR_TAG_SELECTORS.each_pair do |tag_name, selectors|
            selectors.each { |selector| tag_and_selector << [tag_name, selector] }
          end
        end
      end

      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      attr_reader :parsed_body

      def call
        Parallel.flat_map(self.class.tag_and_selector) do |tag_name, selector|
          parsed_body.css(selector).filter_map do |anchor|
            article_tag = self.class.find_article_tag(anchor, tag_name)

            ArticleExtractor.new(article_tag).extract if article_tag
          end
        end
      end
    end
  end
end
