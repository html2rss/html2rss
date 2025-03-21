# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class SemanticHtml
        ##
        # ArticleExtractor is responsible for extracting the details of an article.
        # It focuses on finding a headline first, and from it traverse as much as possible,
        # to find the DOM upwards to find the other details.
        class Extractor
          INVISIBLE_CONTENT_TAG_SELECTORS = %w[svg script noscript style template].to_set.freeze
          HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
          NOT_HEADLINE_SELECTOR = (HEADING_TAGS.map { |selector| ":not(#{selector})" } +
                                   INVISIBLE_CONTENT_TAG_SELECTORS.to_a).freeze

          def self.visible_text_from_tag(tag, separator: ' ')
            text = if (children = tag.children).empty?
                     tag.text.strip
                   else
                     children.filter_map do |child|
                       next if INVISIBLE_CONTENT_TAG_SELECTORS.include?(child.name)

                       visible_text_from_tag(child)
                     end.join(separator)
                   end

            return if (sanitized_text = text.gsub(/\s+/, ' ').strip).empty?

            sanitized_text
          end

          def initialize(article_tag, url:)
            raise ArgumentError, 'article_tag is required' unless article_tag

            @article_tag = article_tag
            @url = url
          end

          # @return [Hash, nil] The scraped article or nil.
          def call
            @heading = find_heading || closest_anchor || return

            @extract_url = find_url

            {
              title: extract_title,
              url: extract_url,
              image: extract_image,
              description: extract_description,
              id: generate_id,
              published_at: extract_published_at
            }
          end

          private

          attr_reader :article_tag, :url, :heading, :extract_url

          ##
          # Find the heading of the article.
          # @return [Nokogiri::XML::Node, nil]
          def find_heading
            heading_tags = article_tag.css(HEADING_TAGS.join(',')).group_by(&:name)

            return if heading_tags.empty?

            smallest_heading = heading_tags.keys.min
            heading_tags[smallest_heading]&.max_by { |tag| visible_text_from_tag(tag)&.size.to_i }
          end

          def visible_text_from_tag(tag, separator: ' ') = self.class.visible_text_from_tag(tag, separator:)

          def closest_anchor
            SemanticHtml.find_closest_selector(heading || article_tag,
                                               selector: 'a[href]:not([href=""])')
          end

          def find_url
            href = closest_anchor&.[]('href')

            return if (parts = href.to_s.split('#')).empty?

            Utils.build_absolute_url_from_relative(parts.first.strip, url)
          end

          def extract_title
            if heading && (heading.children.empty? || heading.text)
              visible_text_from_tag(heading)
            else
              visible_text_from_tag(article_tag.css(HEADING_TAGS.join(','))
                                               .max_by { |tag| tag.text.size })

            end
          end

          def extract_image
            Image.call(article_tag, url:)
          end

          def extract_description
            text = visible_text_from_tag(article_tag.css(NOT_HEADLINE_SELECTOR), separator: '<br>')
            return text if text

            description = visible_text_from_tag(article_tag)
            return nil unless description

            description.strip!
            description.empty? ? nil : description
          end

          def generate_id
            [
              article_tag['id'],
              article_tag.at_css('[id]')&.attr('id'),
              extract_url&.path,
              extract_url&.query
            ].compact.reject(&:empty?).first
          end

          # @see https://developer.mozilla.org/en-US/docs/Web/API/HTMLTimeElement/dateTime
          def extract_published_at
            times = article_tag.css('time[datetime]')
                               .filter_map do |tag|
              DateTime.parse(tag['datetime'])
            rescue ArgumentError, TypeError
              nil
            end

            times.min
          end
        end
      end
    end
  end
end
