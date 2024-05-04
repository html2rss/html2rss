# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Extracts articles by looking for <script type="application/ld+json"> tag.
    #
    # See:
    # 1. https://schema.org/NewsArticle
    # 2. https://developers.google.com/search/docs/appearance/structured-data/article#microdata
    class SemanticHtml
      TAG_SELECTOR = 'article a[href]'

      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      attr_reader :parsed_body

      ##
      # @return [Array<Hash>] the extracted articles
      def call
        anchors = parsed_body.css(TAG_SELECTOR)

        anchors.map do |anchor|
          article_tag = anchor.parent

          while (name = article_tag.name) != 'article'
            next if name == 'body'

            article_tag = article_tag.parent
          end

          extract_article(article_tag)
        end
      end

      def self.articles?(parsed_body)
        parsed_body.css(TAG_SELECTOR).any?
      end

      def extract_article(article) # rubocop:disable Metrics/MethodLength
        heading = heading(article)

        title = title(heading)
        link = link(article, heading)
        description = description(article, heading)

        {
          id: nil,
          title:,
          link:,
          image: article.css('img')&.first&.[]('src'),
          description:
        }
      end

      def heading(article)
        heading_tags = article.css('h1, h2, h3, h4, h5, h6').group_by(&:name)
        lowest_heading_tag_name = heading_tags.keys.min

        heading_tags[lowest_heading_tag_name].max_by { |h| h.text.size }
      end

      def title(heading) = extract_text(heading)

      def extract_text(tag, separator: ' ')
        text = case tag.children.size
               when 0
                 tag.text
               when (1..)
                 tag.children.filter_map { |tag| extract_text(tag) }.join(separator)
               end

        text.gsub(/\s+/, ' ').strip
      end

      # Assumes a link closer to the headline is the correct one.
      # Falls back to first link in article.
      def link(article, heading = nil)
        first_link = article.css('a').first['href']

        if !heading && (down = heading.css('a').first['href'])
          down
        else
          first_link
        end
      end

      def description(article, heading = nil)
        text = extract_text(article.css('p'))

        return text if (text && text != '') || !heading

        extract_text(article).gsub(/\s+/, ' ').gsub(extract_text(heading), '').strip
      end
    end
  end
end
