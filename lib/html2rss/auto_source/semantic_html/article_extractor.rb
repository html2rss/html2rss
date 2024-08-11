# frozen_string_literal: true

module Html2rss
  class AutoSource
    class SemanticHtml
      ##
      # ArticleExtractor is responsible for extracting the details of an article .
      # It focuses on finding a headline first, and from it traverse as much as possible,
      # to find the DOM upwards to find the other details.
      class ArticleExtractor
        INVISIBLE_CONTENT_TAG_SELECTORS = %w[svg script noscript style template].freeze
        NOT_HEADLINE_SELECTOR = SemanticHtml::HEADING_TAGS.map { |selector| ":not(#{selector})" }
                                                          .concat(INVISIBLE_CONTENT_TAG_SELECTORS)
                                                          .freeze
        def initialize(article_tag, url:)
          @article_tag = article_tag
          @url = url
        end

        # @return [Hash] The extracted article or nil if no article could be extracted.
        def extract
          unless heading
            Log.debug "No heading in <#{article_tag.name}> article found: #{article_tag}"
            return
          end

          { title: extract_title,
            url: extract_url,
            image: extract_image,
            description: extract_description,
            id: generate_id,
            published_at: extract_published_at }
        end

        private

        def extract_published_at
          times = article_tag.css('time[datetime]').filter_map { |time| time['datetime']&.strip }

          return nil if times.empty?

          times.filter_map do |time|
            DateTime.parse(time)
          rescue StandardError
            nil
          end.min
        end

        attr_reader :article_tag, :url

        def heading
          return @heading if defined?(@heading)

          heading_tags = article_tag.css(SemanticHtml::HEADING_TAGS.join(',')).group_by(&:name)

          if heading_tags.empty?
            Log.debug "No heading in <#{article_tag.name}> article found: #{article_tag}"
            return
          end

          smallest_heading = heading_tags.keys.min
          @heading = heading_tags[smallest_heading].max_by { |h| h.text.size }
        end

        def extract_title
          return extract_text(heading) if heading&.text

          largest_tag = article_tag.css(SemanticHtml::HEADING_TAGS.join(',')).max_by { |tag| tag.text.size }

          extract_text(largest_tag) if largest_tag
        end

        def extract_url
          return @extract_url if defined?(@extract_url)

          closest_anchor = find_closest_anchor(heading || article_tag)
          href = closest_anchor['href']&.split('#')&.first&.strip

          return if href.to_s.empty?

          @extract_url = Utils.build_absolute_url_from_relative(href, url)
        end

        def find_closest_anchor(element)
          element.css('a[href]').first || find_closest_anchor_upwards(element)
        end

        def find_closest_anchor_upwards(element)
          while element
            anchor = element.at_css('a[href]')
            return anchor if anchor

            element = element.parent
          end
          nil
        end

        # @return [Adressable::URI, nil]
        def extract_image
          src = article_tag.css('img[src]').first&.[]('src')

          src ||= article_tag.css('source[srcset]')
                             .flat_map { |source| source['srcset'].split(',') }
                             .max_by { |source| source ? source.size : 0 }

          Utils.build_absolute_url_from_relative(src, url) if src
        end

        def extract_description
          text = extract_text(article_tag.css(NOT_HEADLINE_SELECTOR), separator: '<br>')
          return text if text

          description = extract_text(article_tag)
          return nil unless description

          title_text = heading&.text
          description.gsub!(title_text, '') if title_text
          description.strip!
          description.empty? ? nil : description
        end

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
          [article_tag['id'], article_tag.at_css('[id]')&.attr('id'), extract_url&.path].compact.reject(&:empty?).first
        end
      end
    end
  end
end
