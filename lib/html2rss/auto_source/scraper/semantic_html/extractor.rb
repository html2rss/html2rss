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
          INVISIBLE_CONTENT_TAG_SELECTORS = %w[svg script noscript style template].freeze
          NOT_HEADLINE_SELECTOR = (SemanticHtml::HEADING_TAGS.map { |selector| ":not(#{selector})" } +
                                   INVISIBLE_CONTENT_TAG_SELECTORS).freeze

          def initialize(article_tag, url:)
            @article_tag = article_tag
            @url = url
            @heading = find_heading
            @extract_url = find_url
          end

          # @return [Hash, nil] The scraped article or nil.
          def call
            return unless heading

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

          def extract_published_at
            times = article_tag.css('time[datetime]')
                               .filter_map do |tag|
              DateTime.parse(tag['datetime'])
            rescue ArgumentError, TypeError
              nil
            end

            times.min
          end

          def find_heading
            heading_tags = article_tag.css(SemanticHtml::HEADING_TAGS.join(',')).group_by(&:name)
            smallest_heading = heading_tags.keys.min
            heading_tags[smallest_heading]&.max_by { |tag| tag.text.size }
          end

          def extract_title
            return extract_text_from_tag(heading) if heading&.text

            largest_tag = article_tag.css(SemanticHtml::HEADING_TAGS.join(',')).max_by { |tag| tag.text.size }
            extract_text_from_tag(largest_tag)
          end

          def extract_description
            text = extract_text_from_tag(article_tag.css(NOT_HEADLINE_SELECTOR), separator: '<br>')
            return text if text

            description = extract_text_from_tag(article_tag)
            return nil unless description

            title_text = heading&.text
            description.gsub!(title_text, '') if title_text
            description.strip!
            description.empty? ? nil : description
          end

          def find_url
            closest_anchor = SemanticHtml.find_closest_selector(heading || article_tag,
                                                                selector: 'a[href]:not([href=""])')
            href = closest_anchor&.[]('href')&.split('#')&.first&.strip
            Utils.build_absolute_url_from_relative(href, url) unless href.to_s.empty?
          end

          def extract_image
            img_src = extract_image_from_img(article_tag) ||
                      extract_image_from_source(article_tag) ||
                      extract_image_from_style(article_tag)
            Utils.build_absolute_url_from_relative(img_src, url) if img_src
          end

          def extract_image_from_img(article_tag)
            article_tag.at_css('img[src]')&.[]('src')
          end

          def extract_image_from_source(article_tag)
            article_tag.css('source[srcset]')
                       .flat_map { |source| source['srcset'].split(',') }
                       .map { |srcset| srcset.split.first.strip }.max_by(&:size)
          end

          def extract_image_from_style(article_tag)
            article_tag.css('[style*="background-image"]')
                       .map { |tag| tag['style'][/url\(['"]?(.*?)['"]?\)/, 1] }
                       .keep_if { |src| src&.start_with?('data:') }
                       .max_by(&:size)
          end

          def extract_text_from_tag(tag, separator: ' ')
            children = tag.children
            text = if children.empty?
                     tag.text
                   else
                     children.filter_map { |child| extract_text_from_tag(child) }.join(separator)
                   end

            sanitized_text = text.gsub(/\s+/, ' ').strip
            sanitized_text unless sanitized_text.empty?
          end

          def generate_id
            [article_tag['id'], article_tag.at_css('[id]')&.attr('id'),
             extract_url&.path].compact.reject(&:empty?).first
          end
        end
      end
    end
  end
end
