# frozen_string_literal: true

module Html2rss
  class AutoSource
    module ArticleRules
      ##
      # Leftover visible-text keep/drop for article descriptions.
      # Split once on block newlines; Date and Category consume the same keepers.
      module Description
        # Listing section names that are chrome, not a dek.
        SECTION_NAMES = Set['press releases'].freeze
        # An ASCII digit: every {DATE_SHAPES} entry needs one.
        DIGIT = /\d/
        # Skip date detection / DateTime.parse above this length.
        MAX_DATE_CHARS = 128
        # Optional type-chip / clock separators (ASCII/en/em dash, pipe, bullet).
        CHIP_SEPARATORS = [' - ', ' – ', ' — ', ' | ', ' • '].freeze
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
          # @param vocabulary [Vocabulary::Scope] the page language's scope, read for type chips
          # @param title [String, nil]
          # @param classifier [LinkDestination::TextClassifier] the page's label reader (memoizing within a run)
          # @return [String, nil]
          def from_lines(lines, vocabulary:, title: nil, classifier: LinkDestination::TextClassifier.for(vocabulary))
            kept = Array(lines).select { |line| keep?(line, vocabulary:, title:, classifier:) }
            kept.empty? ? nil : kept.join("\n")
          end

          ##
          # @param line [String, nil]
          # @param vocabulary [Vocabulary::Scope] the page language's scope, read for type chips
          # @param title [String, nil]
          # @param type_chips [Boolean] whether whole-line type chips are leftover chrome
          # @param classifier [LinkDestination::TextClassifier] the page's label reader
          # @return [Boolean]
          def keep?(line, vocabulary:, title: nil, type_chips: true,
                    classifier: LinkDestination::TextClassifier.for(vocabulary))
            normalized = normalize(line)
            return false if normalized.empty?

            !chrome?(normalized, vocabulary, title:, type_chips:, classifier:)
          end

          ##
          # @param line [String, nil]
          # @return [Boolean]
          def date_shaped?(line)
            return false unless line.to_s.match?(DIGIT) # every date shape holds a digit

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

          # A chip beside a date is peeled whatever the page language: a word that is no marker on a Chinese page
          # (+独自+) is still a type chip once a date stands next to it.
          def type_chip?(text) = Article::Title::TYPE_MARKERS.include?(text.downcase)

          def clock_zone?(text) = Article::Title.clock_piece?(text)

          def chrome?(normalized, vocabulary, title:, type_chips:, classifier:)
            key = normalized.downcase
            classifier.read_more?(normalized) ||
              (type_chips && vocabulary.type_markers.include?(key)) ||
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
