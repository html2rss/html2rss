# frozen_string_literal: true

require 'addressable'
require 'parallel'
require 'set'

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
        'article' => ['article :not(article) a[href]'],
        'section' => ['section :not(section) a[href]'],
        'tr' => ['table tr > td a[href]'],
        'li' => ['li :not(li) a[href]'],
        'div' => ['div > a[href]']
      }.freeze

      ARTICLE_TAGS = ANCHOR_TAG_SELECTORS.keys
      INVISIBLE_CONTENT_TAG_SELECTORS = %w[svg script noscript style template].freeze
      HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].to_set

      NOT_HEADLINE_SELECTOR = HEADING_TAGS.to_a.map { |selector| ":not(#{selector})" }
                                          .concat(INVISIBLE_CONTENT_TAG_SELECTORS)
                                          .join(',')
                                          .freeze

      # TODO: also handle <h2><a href>...</a></h2> as article
      # TODO: also handle <X class="article"><a href>...</a></X> as article

      def self.articles?(parsed_body)
        ANCHOR_TAG_SELECTORS.each_value do |selectors|
          return true if parsed_body.css(selectors.join(', ')).any?
        end
        false
      end

      def self.find_article_tag(anchor, tag_name)
        article_tag = anchor.parent
        article_tag = article_tag.parent while article_tag && article_tag.name != tag_name
        article_tag
      end

      ##
      # With multiple articles sharing the same URL, build one out of them, by
      # keeping the longest attribute values.
      def self.keep_longest_attributes(articles)
        grouped_by_url = articles.group_by { |article| article[:url] }
        grouped_by_url.map do |_url, articles_with_same_url|
          longest_attributes_article = articles_with_same_url.first
          articles_with_same_url.each do |article|
            article.each do |key, value|
              longest_attributes_article[key] = value if value && value.size > longest_attributes_article[key].to_s.size
            end
          end
          longest_attributes_article
        end
      end

      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      attr_reader :parsed_body

      def call
        articles = Parallel.flat_map(ANCHOR_TAG_SELECTORS.to_a) do |tag_name, selectors|
          parsed_body.css(selectors.join(', ')).filter_map do |anchor|
            article_tag = self.class.find_article_tag(anchor, tag_name)
            ArticleExtractor.new(article_tag).extract if article_tag
          end
        end

        clean_articles(articles)
      end

      def clean_articles(articles)
        articles = self.class.keep_longest_attributes(articles)
        articles = deduplicate_by_url!(articles)
        articles = remove_short_title_articles!(articles)
        keep_only_http_urls!(articles)
      end

      def deduplicate_by_url!(articles)
        articles.uniq { |article| article[:url] }
      end

      def remove_short_title_articles!(articles, min_words: 2)
        articles.reject { |article| article[:title]&.split&.size&.< min_words }
      end

      def keep_only_http_urls!(articles)
        articles.select { |article| article[:url]&.start_with?('http') }
      end
    end
  end
end
