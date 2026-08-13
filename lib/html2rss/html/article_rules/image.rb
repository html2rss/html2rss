# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic image URL selection (srcset sizing, CSS background urls).
      module Image
        # Caps attribute size before Regexp so CodeQL rb/polynomial-redos stays bounded.
        MAX_ATTR_CHARS = 4_096
        # Matches a srcset candidate URL and its width/height descriptor.
        SRCSET_PAIR = /(\S+)\s+(\d+w|\d+h)[\s,]?/
        # Captures a CSS `url(...)` background image candidate.
        STYLE_URL = /url\(['"]?(.*?)['"]?\)/

        class << self
          ##
          # @param srcset_strings [Array<String>] raw srcset attribute values
          # @return [String, nil] URL of the largest width/height candidate
          def largest_from_srcsets(srcset_strings)
            by_size = {}
            Array(srcset_strings).each { |srcset| merge_srcset!(by_size, srcset) }
            by_size[by_size.keys.max]
          end

          ##
          # @param style_strings [Array<String>] CSS style attribute values
          # @return [String, nil] longest non-data background url
          def best_from_styles(style_strings)
            Array(style_strings)
              .filter_map { |style| style_url(style) }
              .reject { |src| src.start_with?('data:') }
              .max_by(&:size)
          end

          private

          def merge_srcset!(by_size, srcset)
            s = srcset.to_s
            return if s.length > MAX_ATTR_CHARS

            s.scan(SRCSET_PAIR) do |url, width|
              next if url.nil? || url.start_with?('data:')

              by_size[descriptor_size(width)] = url.strip
            end
          end

          def style_url(style)
            s = style.to_s
            return if s.length > MAX_ATTR_CHARS

            s[STYLE_URL, 1]
          end

          def descriptor_size(width)
            width.to_i.zero? ? 0 : width.scan(/\d+/).first.to_i
          end
        end
      end
    end
  end
end
