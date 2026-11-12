# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # The one rule for which HTML elements become enclosures, and their URL/type normalization.
      #
      # DOM-agnostic: {ArticleExtractor::EnclosureExtractor} (Nokogiri) and {SstArticleExtractor} (SST)
      # only visit {ELEMENT_NAMES}, adapt their node API to {.from_element} and pass the result through
      # {.unique}. Images (+img[src]+), players (+audio[src]+, +video[src]+), a player's +source[src]+ with
      # its +type+, and file links ({FILE_LINK}) qualify; an +iframe+ (embed player page) never does,
      # and only an http(s) URL is one (no +data:+, +blob:+, +javascript:+ or +mailto:+).
      module Enclosure
        # A link to a downloadable document or archive: its path (before any query or fragment) ends in
        # +.pdf+, +.zip+, +.tar.gz+ or +.tgz+, in any case.
        FILE_LINK = /\A[^?#]*\.(?:pdf|zip|tar\.gz|tgz)(?:[?#]|\z)/i
        # Element names that may carry an enclosure.
        ELEMENT_NAMES = %w[img audio video source a].freeze
        # Players whose own +src+ and inner +source+ elements name a media file.
        MEDIA_ELEMENTS = %w[audio video].freeze

        class << self
          ##
          # The enclosure an HTML element stands for, if any. A player's file carries the player as its
          # kind, so an untyped file without a media extension is still audio or video
          # ({Article::Enclosure::KIND_TYPES}).
          #
          # @param name [String] element name (lower case)
          # @param base_url [String, Html2rss::Url]
          # @param src [String, nil] the element's +src+ attribute
          # @param href [String, nil] the element's +href+ attribute
          # @param type [String, nil] the element's +type+ attribute
          # @yieldreturn [String, nil] the name of the nearest {MEDIA_ELEMENTS} player around the element (an
          #   ancestor, not only the parent: the HTML4 parser nests sibling +source+ elements), or nil; asked
          #   only for a +source+
          # @return [Hash{Symbol => Object}, nil]
          def from_element(name, base_url, src:, href:, type:)
            case name
            when 'img' then from_image(src, base_url)
            when 'audio', 'video' then from_media(src, type, base_url, kind: name.to_sym)
            when 'source' then from_source(src, type, base_url, yield)
            when 'a' then from_anchor(href, base_url)
            end
          end

          ##
          # @param src [String, nil]
          # @param type [String, nil] declared MIME type; nil lets {Article::Enclosure#type} guess it
          # @param base_url [String, Html2rss::Url, nil]
          # @param kind [Symbol, nil] +:audio+ or +:video+ when the source proves the file's kind
          # @return [Hash{Symbol => Object}, nil] nil unless +src+ resolves to an http(s) URL
          def from_media(src, type, base_url, kind: nil)
            return unless (url = web_url(src, base_url))

            { url:, type:, kind: }.compact
          end

          ##
          # One enclosure per URL, at its first position in document order; a duplicate declaring a type
          # wins over an untyped one (+<video src=x><source src=x type=video/webm>+).
          #
          # @param enclosures [Array<Hash{Symbol => Object}>] {.from_element} results in document order
          # @return [Array<Hash{Symbol => Object}>]
          def unique(enclosures)
            enclosures.group_by { _1[:url] }.map { |_url, same| same.find { _1[:type] } || same.first }
          end

          private

          def from_image(src, base_url)
            return unless (url = web_url(src, base_url))

            { url:, type: Article::Enclosure.guess_content_type_from_url(url, default: 'image/jpeg') }
          end

          def from_source(src, type, base_url, player)
            from_media(src, type, base_url, kind: player.to_sym) if player
          end

          def from_anchor(href, base_url)
            return unless href&.match?(FILE_LINK) && (url = web_url(href, base_url))

            { url: }
          end

          # @return [Html2rss::Url, nil] the absolute URL of +ref+ when it is http(s)
          def web_url(ref, base_url)
            return unless ref.to_s.match?(/\S/)

            url = Url.from_relative(ref, base_url)
            url if Url::SUPPORTED_SCHEMES.include?(url.scheme)
          rescue Url::InvalidUrlError
            nil
          end
        end
      end
    end
  end
end
