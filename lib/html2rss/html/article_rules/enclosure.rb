# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # The one rule for which HTML elements become enclosures, and their URL/type normalization.
      #
      # DOM-agnostic: {ArticleExtractor::EnclosureExtractor} (Nokogiri) and {SstArticleExtractor} (SST)
      # only visit {ELEMENT_NAMES} and adapt their node API to {.from_element}. Images
      # (+img[src]+), players (+audio[src]+, +video[src]+), a player's +source[src]+ with its +type+,
      # and file links ({ARCHIVE_HREF_SUFFIXES}) qualify; an +iframe+ (embed player page) never does.
      module Enclosure
        # Href path suffixes treated as download/archive enclosure links.
        ARCHIVE_HREF_SUFFIXES = %w[.pdf .zip .tar.gz .tgz].freeze
        # Element names that may carry an enclosure.
        ELEMENT_NAMES = %w[img audio video source a].freeze
        # Players whose own +src+ and inner +source+ elements name a media file.
        MEDIA_ELEMENTS = %w[audio video].freeze

        class << self
          ##
          # @param href [String]
          # @return [Boolean]
          def archive_href?(href)
            ARCHIVE_HREF_SUFFIXES.any? { |suffix| href.to_s.end_with?(suffix) }
          end

          ##
          # The enclosure an HTML element stands for, if any.
          #
          # @param name [String] element name (lower case)
          # @param base_url [String, Html2rss::Url]
          # @param src [String, nil] the element's +src+ attribute
          # @param href [String, nil] the element's +href+ attribute
          # @param type [String, nil] the element's +type+ attribute
          # @yieldreturn [Boolean] whether the element sits inside a {MEDIA_ELEMENTS} player (an ancestor, not
          #   only the parent: the HTML4 parser nests sibling +source+ elements); asked only for a +source+
          # @return [Hash{Symbol => Object}, nil]
          def from_element(name, base_url, src:, href:, type:)
            case name
            when 'img' then from_image(src, base_url)
            when 'audio', 'video' then from_media(src, type, base_url)
            when 'source' then from_media(src, type, base_url) if yield
            when 'a' then from_anchor(href, base_url)
            end
          end

          ##
          # @param src [String]
          # @param type [String, nil] declared MIME type; nil lets {Article::Enclosure#type} guess it
          # @param base_url [String, Html2rss::Url]
          # @return [Hash{Symbol => Object}, nil]
          def from_media(src, type, base_url)
            return if src.to_s.empty?

            { url: Url.from_relative(src, base_url), type: }
          end

          private

          def from_image(src, base_url)
            return unless Image.remote_src?(src)

            abs = Url.from_relative(src, base_url)
            { url: abs, type: Article::Enclosure.guess_content_type_from_url(abs, default: 'image/jpeg') }
          end

          def from_anchor(href, base_url)
            return unless archive_href?(href)

            abs = Url.from_relative(href, base_url)
            type = href.end_with?('.pdf') ? Article::Enclosure.guess_content_type_from_url(abs) : 'application/zip'
            { url: abs, type: }
          end
        end
      end
    end
  end
end
