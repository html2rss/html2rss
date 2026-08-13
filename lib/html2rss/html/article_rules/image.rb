# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic image URL selection (srcset sizing, CSS background urls).
      #
      # Parsers are intentional linear string scans (no Regexp) so hostile HTML
      # attributes cannot trigger polynomial-time Regexp backtracking flagged by
      # CodeQL +rb/polynomial-redos+. On typical inputs Regexp is often faster;
      # absolute cost of the linear path stays in the low microseconds.
      module Image
        # HTML/CSS whitespace code points treated as token separators in srcset.
        WHITESPACE = [' ', "\t", "\n", "\r", "\f"].freeze
        # Optional quoting characters around a CSS `url(...)` value.
        QUOTES = ['"', "'"].freeze
        # Srcset width/height descriptor suffixes (`Nw` / `Nh`).
        DESCRIPTOR_UNITS = %w[w h].freeze

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
              .filter_map { |style| first_css_url(style.to_s) }
              .reject { |src| src.start_with?('data:') }
              .max_by(&:size)
          end

          private

          def merge_srcset!(by_size, srcset)
            each_srcset_candidate(srcset.to_s) do |url, size|
              next if url.start_with?('data:')

              by_size[size] = url
            end
          end

          # Walks srcset as URL token + optional `Nw`/`Nh` descriptor pairs.
          # Commas inside URLs are allowed; candidates are delimited by whitespace
          # before a width/height descriptor.
          def each_srcset_candidate(string, &)
            i = 0
            length = string.length
            while i < length
              i = skip_separators(string, i, length)
              break if i >= length

              i = yield_srcset_pair(string, i, length, &)
            end
          end

          def yield_srcset_pair(string, index, length)
            url, index = read_token(string, index, length)
            index = skip_whitespace(string, index, length)
            size, index = read_descriptor_size(string, index, length)
            yield url, size if size
            index
          end

          def read_token(string, index, length)
            start = index
            index += 1 while index < length && !whitespace?(string[index])
            [string[start, index - start], index]
          end

          def read_descriptor_size(string, index, length)
            start = index
            index += 1 while index < length && digit?(string[index])
            return [nil, index] unless index > start && index < length && DESCRIPTOR_UNITS.include?(string[index])

            size = string[start, index - start].to_i
            [size, index + 1]
          end

          def first_css_url(string)
            pos = string.index('url(')
            return unless pos

            extract_css_url_body(string, pos + 4)
          end

          def extract_css_url_body(string, index)
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

          def skip_separators(string, index, length)
            index += 1 while index < length && separator?(string[index])
            index
          end

          def skip_whitespace(string, index, length)
            index += 1 while index < length && whitespace?(string[index])
            index
          end

          def separator?(char) = whitespace?(char) || char == ','

          def whitespace?(char) = WHITESPACE.include?(char)

          def digit?(char) = char.between?('0', '9')
        end
      end
    end
  end
end
