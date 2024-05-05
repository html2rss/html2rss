# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Extracts articles by looking for <article> tags containing an <a href> tag.
    # An article is not considered an article without having an URL.
    #
    # See:
    # 1. https://developer.mozilla.org/en-US/docs/Web/HTML/Element/article
    class SemanticHtml
      ANCHOR_TAG_SELECTOR = 'article :not(article) a[href]'

      # TODO: also handle <h2><a href>...</a></h2> as article
      # TODO: also handle <X class="article"><a href>...</a></X> as article

      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      attr_reader :parsed_body

      def self.articles?(parsed_body)
        parsed_body.css(ANCHOR_TAG_SELECTOR).any?
      end

      ##
      # @return [Array<Hash>] the extracted articles
      def call
        anchors = parsed_body.css(ANCHOR_TAG_SELECTOR)

        anchors.filter_map do |anchor|
          article_tag = anchor.parent

          while (name = article_tag.name) != 'article'
            next if name == 'body'

            article_tag = article_tag.parent
          end

          extract_article(article_tag)
        end
      end

      def extract_article(article)
        # TODO: extract the article into a separate class, get rid of passing `article` around to methods

        heading = heading(article)

        {
          id: id(article),
          title: title(article, heading),
          url: url(article, heading),
          image: image(article),
          description: description(article, heading)
        }
      end

      HEADING_TAGS_SELECTOR = 'h1, h2, h3, h4, h5, h6'
      NOT_HEADLINE_SELECTOR = HEADING_TAGS_SELECTOR.split(',')
                                                   .map { |selector| ":not(#{selector})" }
                                                   .join(', ')
                                                   .freeze
      ##
      # Finds the heading tag of an article.
      #
      # If multiple headings are found, the smallest heading tag (h1 is smaller than h2) is returned.
      # If multiple tags of the same size are found, the one with the longest text is returned.
      # If no heading is found, nil is returned.
      #
      # @return [Nokogiri::XML::Element, nil] a heading tag or nil if none found
      def heading(article)
        heading_tags = article.css(HEADING_TAGS_SELECTOR).group_by(&:name)

        return if heading_tags.empty?

        heading_tags[heading_tags.keys.min].max_by { |h| h.text.size }
      end

      # @return [String, nil]
      def id(article)
        if (id = article['id'] && !id.empty?)
          id
        else
          article.css('*[id]:not([id=""])')&.map { |tag| tag['id'] }&.first
        end
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
      def url(article, heading = nil)
        if !heading && (down = heading&.css('a')&.first&.[]('href'))
          down
        else
          article.css('a').first['href']
        end
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
