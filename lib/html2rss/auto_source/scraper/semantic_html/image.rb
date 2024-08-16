# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      class SemanticHtml
        ##
        # Image is responsible for extracting image URLs the article_tag.
        class Image
          def self.call(article_tag, url:)
            img_src = from_source(article_tag) ||
                      from_img(article_tag) ||
                      from_style(article_tag)

            Utils.build_absolute_url_from_relative(img_src, url) if img_src
          end

          def self.from_img(article_tag)
            article_tag.at_css('img[src]:not([src^="data"])')&.[]('src')
          end

          ##
          # Extracts the largest image source from the srcset attribute
          # of an img tag or a source tag inside a picture tag.
          #
          # @see <https://developer.mozilla.org/en-US/docs/Learn/HTML/Multimedia_and_embedding/Responsive_images>
          # @see <https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#srcset>
          # @see <https://developer.mozilla.org/en-US/docs/Web/HTML/Element/picture>
          def self.from_source(article_tag) # rubocop:disable Metrics/AbcSize
            hash = article_tag.css('img[srcset], picture > source[srcset]')
                              .flat_map { |source| source['srcset'].to_s.split(',') }
                              .filter_map do |line|
              width, url = line.split.reverse
              next if url.nil? || url.start_with?('data:')

              width_value = width.to_i.zero? ? 0 : width.scan(/\d+/).first.to_i

              [width_value, url.strip]
            end.to_h

            hash[hash.keys.max]
          end

          def self.from_style(article_tag)
            article_tag.css('[style*="url"]')
                       .map { |tag| tag['style'][/url\(['"]?(.*?)['"]?\)/, 1] }
                       .reject { |src| !src || src.start_with?('data:') }
                       .max_by(&:size)
          end
        end
      end
    end
  end
end
