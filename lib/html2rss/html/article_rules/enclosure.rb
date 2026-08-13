# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic enclosure URL/type normalization.
      module Enclosure
        ARCHIVE_HREF_SUFFIXES = %w[.pdf .zip .tar.gz .tgz].freeze

        class << self
          ##
          # @param href [String]
          # @return [Boolean]
          def archive_href?(href)
            ARCHIVE_HREF_SUFFIXES.any? { |suffix| href.to_s.end_with?(suffix) }
          end

          ##
          # @param src [String]
          # @param base_url [String, Html2rss::Url]
          # @return [Hash{Symbol => Object}, nil]
          def from_image(src, base_url)
            return if src.to_s.empty?

            abs = Url.from_relative(src, base_url)
            { url: abs, type: Article::Enclosure.guess_content_type_from_url(abs, default: 'image/jpeg') }
          end

          ##
          # @param src [String]
          # @param type [String, nil]
          # @param base_url [String, Html2rss::Url]
          # @return [Hash{Symbol => Object}, nil]
          def from_media(src, type, base_url)
            return if src.to_s.empty?

            { url: Url.from_relative(src, base_url), type: }
          end

          ##
          # @param src [String]
          # @param base_url [String, Html2rss::Url]
          # @return [Hash{Symbol => Object}, nil]
          def from_iframe(src, base_url)
            return if src.to_s.empty?

            abs = Url.from_relative(src, base_url)
            { url: abs, type: Article::Enclosure.guess_content_type_from_url(abs, default: 'text/html') }
          end

          ##
          # @param href [String]
          # @param base_url [String, Html2rss::Url]
          # @return [Hash{Symbol => Object}, nil]
          def from_anchor(href, base_url)
            return if href.to_s.empty?

            abs = Url.from_relative(href, base_url)
            type = if href.end_with?('.pdf')
                     Article::Enclosure.guess_content_type_from_url(abs)
                   else
                     'application/zip'
                   end
            { url: abs, type: }
          end
        end
      end
    end
  end
end
