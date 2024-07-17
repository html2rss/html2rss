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
      # rubocop:disable Layout/HashAlignment
      ANCHOR_TAG_SELECTORS = {
        'article' => ['article :not(article) a[href]'],
        'section' => ['section :not(section) a[href]'],
        'tr' =>      ['table tr > td a[href]'],
        'li' =>      ['li :not(li) a[href]'],
        'div' =>     ['div > a[href]']
      }.freeze
      # rubocop:enable Layout/HashAlignment

      ARTICLE_TAGS = ANCHOR_TAG_SELECTORS.keys
      INVISIBLE_CONTENT_TAG_SELECTORS = %w[svg script noscript style template].freeze

      HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].to_set

      NOT_HEADLINE_SELECTOR = HEADING_TAGS.to_a.map { |selector| ":not(#{selector})" }
                                          .concat(INVISIBLE_CONTENT_TAG_SELECTORS)
                                          .join(',')
                                          .freeze

      # TODO: also handle <h2><a href>...</a></h2> as article
      # TODO: also handle <X class="article"><a href>...</a></X> as article

      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      attr_reader :parsed_body

      def self.articles?(parsed_body)
        ANCHOR_TAG_SELECTORS.each_pair do |_tag, selectors|
          return true if parsed_body.css(selectors.join(', ')).any?
        end

        false
      end

      ##
      # @return [Array<Hash>] the extracted articles
      def call # rubocop:disable Metrics/MethodLength
        articles = Parallel.map(ANCHOR_TAG_SELECTORS.to_a) do |tag, selectors|
          parsed_body.css(selectors.join(', ')).filter_map do |anchor|
            article_tag = anchor.parent

            while (name = article_tag.name) != tag
              next if name == 'body'

              article_tag = article_tag.parent
            end

            extract_article(article_tag)
          end
        end

        articles.flatten!

        articles = self.class.keep_longest_attributes(articles)

        Html2rss::AutoSource.remove_titleless_articles!(articles)

        articles
      end

      ##
      # With multiple articles sharing the same URL, build one out of them, by
      # keeping the longest attribute values.
      def self.keep_longest_attributes(articles) # rubocop:disable Metrics/AbcSize
        grouped_by_url = Hash.new { |h, k| h[k] = [] }

        articles.each { |article| grouped_by_url[article[:url]] << article }

        grouped_by_url.each_pair.map do |url, same_url_articles|
          builder = LongestStringBuilder.new(url:)

          same_url_articles.each do |article|
            article.each_pair { |key, value| builder.add(key, value) }
          end

          builder.to_h
        end
      end

      class LongestStringBuilder
        def initialize(**initial_args)
          @hash = Hash.new { |h, k| h[k] = '' }

          initial_args.each_pair { |key, string| add(key, string) }
        end

        def add(key, string)
          return if !key || !key.is_a?(Symbol) || !string

          @hash[key] = string if string.size > @hash[key]&.to_s&.size
        end

        def to_h = @hash
      end

      def extract_article(article)
        # TODO: extract the article into a separate class, get rid of passing `article` around to methods

        heading = heading(article)

        scraped_article = {
          title: title(article, heading),
          url: url(article, heading),
          image: image(article),
          description: description(article, heading)
        }
        scraped_article[:id] = generate_id(article, scraped_article)
        scraped_article
      end

      ##
      # Finds the heading tag of an article.
      #
      # If multiple headings are found, the smallest heading tag (h1 is smaller than h2) is returned.
      # If multiple tags of the same size are found, the one with the longest text is returned.
      # If no heading is found, nil is returned.
      #
      # @return [Nokogiri::XML::Element, nil] a heading tag or nil if none found
      def heading(article)
        heading_tags = article.css(HEADING_TAGS).group_by(&:name)

        return if heading_tags.empty?

        heading_tags[heading_tags.keys.min].max_by { |h| h.text.size }
      end

      # @return [String, nil] a derived ID for the article
      def generate_id(article, scraped_article)
        return article['id'] unless article['id'].to_s.empty?

        scraped_article[:url].split('/')[3..].to_a.join('/').split('#').first
      end

      def title(article, heading)
        if heading && (title = extract_text(heading))
          title
        else
          article.css(NOT_HEADLINE_SELECTOR)
                 .filter_map { |tag| extract_text(tag) }
                 .max_by(&:size)
        end
      end

      # @return [String, nil] the text of the tag or nil if empty
      def extract_text(tag, separator: ' ')
        text = case tag.children.size
               when 0
                 tag.text
               when (1..)
                 tag.children.filter_map { |tag| extract_text(tag) }.uniq.join(separator)
               end.dup

        text.gsub!(/\s+/, ' ')
        text.strip!
        text.empty? ? nil : text
      end

      # Assumes a URL closer to the headline is the correct one.
      # Falls back to first URL in article.
      # @return [String, nil] the URL of the article or nil if empty
      def url(article, heading = nil)
        url = if !heading && (down = heading&.css('a')&.first&.[]('href'))
                down
              else
                article.css('a[href]').first['href']
              end

        url&.split('#')&.first
      end

      def image(article)
        # TODO: also try <picture><source srcset> (when an <img> is missing)
        article.css('img[src]')&.first&.[]('src')
      end

      # @return [String, nil] the description of the article or nil if empty
      def description(article, heading = nil)
        text = extract_text(article.css('p, span'), separator: '<br>')

        return text if text || !heading

        # Get all text of the article, but remove the title
        description = extract_text(article).gsub(title(article, heading), '')

        description.strip!

        description.empty? ? nil : description
      end
    end
  end
end
