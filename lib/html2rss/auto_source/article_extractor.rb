# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # ArticleExtractor is responsible for extracting the details of an article from a given
    # Nokogiri element representing an article. It extracts the title, URL, image, and description
    # of the article, and generates an ID for it.
    #
    # The class is designed to work with parsed HTML documents and leverages Nokogiri for
    # parsing and navigating the HTML structure. It aims to identify and extract useful information
    # from typical article structures found on web pages.
    class ArticleExtractor
      def initialize(article_tag)
        @article_tag = article_tag
      end

      def extract
        heading = find_heading
        clean_values({
                       title: extract_title(heading),
                       url: extract_url(heading),
                       image: extract_image,
                       description: extract_description(heading),
                       id: generate_id
                     })
      end

      private

      attr_reader :article_tag

      ##
      # Finds the heading tag of an article.
      #
      # If multiple headings are found, the smallest heading tag (h1 is smaller than h2) is returned.
      # If multiple tags of the same size are found, the one with the longest text is returned.
      # If no heading is found, nil is returned.
      #
      # @return [Nokogiri::XML::Element, nil] a heading tag or nil if none found
      def find_heading
        return @find_heading if defined?(@find_heading)

        heading_tags = article_tag.css(SemanticHtml::HEADING_TAGS.to_a.join(',')).group_by(&:name)
        return if heading_tags.empty?

        smallest_heading = heading_tags.keys.min
        @find_heading = heading_tags[smallest_heading].max_by { |h| h.text.size }
      end

      def extract_title(heading)
        return heading&.text if heading&.text

        largest_tag = article_tag.css(SemanticHtml::NOT_HEADLINE_SELECTOR).max_by { |tag| tag.text.size }
        extract_text(largest_tag) if largest_tag
      end

      # Falls back to longest URL in article.
      # @return [String, nil] the URL of the article or nil if empty
      def extract_url(heading)
        closest_anchor = if heading
                           heading.css('a[href]').first || find_closest_anchor_upwards(heading)
                         else
                           find_closest_anchor_upwards(article_tag)
                         end
        closest_anchor['href']&.split('#')&.first&.strip
      end

      def find_closest_anchor_upwards(element)
        while element
          anchor = element.at_css('a[href]')
          return anchor if anchor

          element = element.parent
        end
        nil
      end

      def extract_image
        img_tag = article_tag.at_css('img[src]') || article_tag.at_css('picture source[srcset]')
        img_tag&.[]('src') || img_tag&.[]('srcset')&.split&.first&.strip
      end

      # @return [String, nil] the description of the article or nil if empty
      def extract_description(heading)
        text = extract_text(article_tag.css('p, span'), separator: '<br>')
        return text if text

        description = extract_text(article_tag)
        return nil unless description

        title_text = heading&.text
        description.gsub!(title_text, '') if title_text
        description.strip!
        description.empty? ? nil : description
      end

      # @return [String, nil] the text of the tag or nil if empty
      def extract_text(tag, separator: ' ')
        text = if tag.children.empty?
                 tag.text
               else
                 tag.children.map { |child| extract_text(child) }.join(separator)
               end
        text.gsub!(/\s+/, ' ')
        text.strip!
        text.empty? ? nil : text
      end

      def generate_id
        article_tag['id'] || generate_id_from_heading
      end

      def generate_id_from_heading
        heading = find_heading
        url_id = extract_url_id(heading)
        return url_id if url_id

        extract_title_id(heading)
      end

      def extract_url_id(heading)
        url = extract_url(heading)
        return unless url

        parts = url.split('/')
        parts[3..]&.join('/')&.split('#')&.first
      end

      def extract_title_id(heading)
        title = extract_title(heading)
        return unless title

        title.downcase.gsub(/\s+/, '-')
      end

      def clean_values(hash)
        hash.transform_values do |value|
          next value unless value.is_a?(String)

          value.gsub!(/[[:space:]]+/, ' ')
          value.strip!
          value.empty? ? nil : value
        end
      end
    end
  end
end
