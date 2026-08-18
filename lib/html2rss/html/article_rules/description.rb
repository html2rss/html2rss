# frozen_string_literal: true

module Html2rss
  module Html
    module ArticleRules
      ##
      # Leftover visible-text keep/drop for article descriptions.
      # Split once on block newlines; Date and Category consume the same keepers.
      module Description
        # CTA lines dropped by whole-line equality (case-insensitive).
        CTA = Set['read more', 'learn more'].freeze
        # Type-chip lines dropped when the whole leftover line is one of these.
        TYPE_CHIPS = Set['news article', 'press release', 'news'].freeze
        # Listing section names that are chrome, not a dek.
        SECTION_NAMES = Set['press releases'].freeze
        # Skip date detection / DateTime.parse above this length.
        MAX_DATE_CHARS = 128
        # Optional type-chip / clock separators (ASCII/en/em dash, pipe, bullet).
        CHIP_SEPARATORS = [' - ', ' – ', ' — ', ' | ', ' • '].freeze
        # Trailing clock plus optional AM/PM and one timezone/offset token (IANA, GMT/UTC offset, or abbrev).
        CLOCK_ZONE = %r{
          \A
          \d{1,2}:\d{2}(?::\d{2})?
          (?:\s*(?:AM|PM))?
          (?:\s+(?:[A-Za-z]+(?:/[A-Za-z_]+)+|(?:GMT|UTC)[+-]\d{1,2}(?::\d{2})?|[A-Za-z]{2,5}))?
          \z
        }ix
        # Whole-line date shapes after normalize (ISO, numeric, day-month, month-day).
        DATE_SHAPES = [
          /\A\d{4}-\d{1,2}-\d{1,2}(?:[T ]\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?\z/i,
          %r{\A\d{1,2}[./-]\d{1,2}[./-]\d{2,4}(?: \d{1,2}:\d{2}(?::\d{2})?)?\z},
          /\A\d{1,2}\.? \p{L}{3,9}\.?\s*,?\s*\d{4}(?: \d{1,2}:\d{2}(?::\d{2})?)?\z/i,
          /\A\p{L}{3,9}\.? \d{1,2}\s*,?\s*\d{4}(?: \d{1,2}:\d{2}(?::\d{2})?)?\z/i
        ].freeze

        class << self
          ##
          # @param text [String, nil]
          # @return [Array<String>]
          def lines_from(text)
            text.to_s.split(/\n+/).map { |line| normalize(line) }.reject(&:empty?)
          end

          ##
          # @param lines [Array<String>, nil]
          # @param title [String, nil]
          # @return [String, nil]
          def from_lines(lines, title: nil)
            kept = Array(lines).select { |line| keep?(line, title:) }
            kept.empty? ? nil : kept.join("\n")
          end

          ##
          # @param line [String, nil]
          # @param title [String, nil]
          # @param type_chips [Boolean] whether whole-line type chips are leftover chrome
          # @return [Boolean]
          def keep?(line, title: nil, type_chips: true)
            normalized = normalize(line)
            return false if normalized.empty?

            !chrome?(normalized, title:, type_chips:)
          end

          ##
          # @param line [String, nil]
          # @return [Boolean]
          def date_shaped?(line)
            core = date_core(line)
            return false if core.empty? || core.length > MAX_DATE_CHARS

            DATE_SHAPES.any? { |shape| core.match?(shape) }
          end

          ##
          # @param line [String, nil]
          # @return [String]
          def date_core(line)
            normalized = normalize(line)
            CHIP_SEPARATORS.each do |sep|
              peeled = peel_separator(normalized, sep)
              return peeled if peeled
            end
            normalized
          end

          private

          def normalize(line) = line.to_s.gsub(/[[:space:]]+/, ' ').strip

          def peel_separator(normalized, sep)
            idx = normalized.rindex(sep)
            return unless idx

            left = normalized[0, idx]
            right = normalized[(idx + sep.length)..]
            return left if type_chip?(right) || clock_zone?(right)
            return right if type_chip?(left)

            nil
          end

          def type_chip?(text) = TYPE_CHIPS.include?(text.downcase)

          def clock_zone?(text) = text.match?(CLOCK_ZONE)

          def chrome?(normalized, title:, type_chips:)
            key = normalized.downcase
            CTA.include?(key) || (type_chips && TYPE_CHIPS.include?(key)) ||
              SECTION_NAMES.include?(key) || normalized.end_with?(':') ||
              date_shaped?(normalized) || title_echo?(key, title)
          end

          def title_echo?(key, title)
            t = title.to_s.strip.downcase
            !t.empty? && key == t
          end
        end
      end
    end
  end
end
