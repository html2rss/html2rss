# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic image URL selection (srcset sizing, CSS background urls).
      #
      # Uses string scans instead of Regexp: CodeQL rb/polynomial-redos flags the
      # prior patterns on uncontrolled HTML attributes, and length guards alone
      # do not clear the query.
      module Image
        # Skip absurdly large attributes before scanning.
        MAX_ATTR_CHARS = 4_096
        # Optional quoting around a CSS `url(...)` value.
        QUOTES = ['"', "'"].freeze
        # Srcset width/height descriptor suffixes.
        UNITS = %w[w h].freeze
        # HTML/CSS whitespace treated as srcset token separators.
        WS = [' ', "\t", "\n", "\r", "\f"].freeze

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

            each_srcset_pair(s) do |url, size|
              next if url.start_with?('data:')

              by_size[size] = url
            end
          end

          # URL token + `Nw`/`Nh` pairs. Commas may appear inside URLs; a candidate
          # boundary is whitespace before a width/height descriptor.
          def each_srcset_pair(string) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
            i = 0
            len = string.length
            while i < len
              i += 1 while i < len && sep?(string[i])
              break if i >= len

              start = i
              i += 1 while i < len && !ws?(string[i])
              url = string[start, i - start]

              i += 1 while i < len && ws?(string[i])
              size_start = i
              i += 1 while i < len && string[i].between?('0', '9')
              next unless i > size_start && i < len && UNITS.include?(string[i])

              yield url, string[size_start, i - size_start].to_i
              i += 1
            end
          end

          def style_url(style)
            s = style.to_s
            return if s.length > MAX_ATTR_CHARS

            pos = s.index('url(')
            return unless pos

            extract_url_body(s, pos + 4)
          end

          def extract_url_body(string, index)
            quote = string[index]
            if QUOTES.include?(quote)
              slice_until(string, index + 1, quote)
            else
              slice_until(string, index, ')')
            end
          end

          def slice_until(string, start, closer)
            close = string.index(closer, start)
            string[start, close - start] if close
          end

          def sep?(char) = ws?(char) || char == ','

          def ws?(char) = WS.include?(char)
        end
      end
    end
  end
end
