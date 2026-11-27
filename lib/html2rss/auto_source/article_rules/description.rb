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
        # A whole-line reading time ("3 Min", "5 Minuten", "4 minutes read").
        READING_TIME = /\A\d{1,3}\s?(?:min(?:\.|uten|utes?)?)(?:\s(?:read|lesezeit))?\z/i
        # A short leading line that opens with a photo-credit label.
        CREDIT_LEAD = /\A(?:©|(?:foto|photo|bild)\s?:)/i
        # A host name such as "example.com" closing a credit line ("Name – example.com").
        CREDIT_HOST = /\A\p{L}[\p{L}\d-]{0,30}(?:\.[\p{L}\d-]{1,30}){0,3}\.\p{L}{2,12}\z/
        # Longest line that counts as a credit or a label rather than prose.
        MAX_LABEL_CHARS = 60
        # One to four words, as a leading label holds ("Category SDK Published").
        LABEL_SHAPE = /\A\S+(?:\s\S+){0,3}\z/
        # A line must be at least this long to count as the paragraph a leading label belongs to.
        MIN_PARAGRAPH_CHARS = 40
        # List markup prefix the text reader puts on list items.
        LIST_MARK = /\A- /
        # An item of this length without sentence-ending punctuation is a fragment, not a sentence.
        MAX_FRAGMENT_CHARS = 40
        # Closing punctuation of a sentence or lead-in.
        SENTENCE_END = /[.!?…:]\z/

        class << self
          ##
          # @param text [String, nil]
          # @return [Array<String>]
          def lines_from(text)
            lines = text.to_s.split(/\n+/).map { |line| normalize(line) }.reject(&:empty?)
            lines.slice_when { |a, b| a.match?(LIST_MARK) != b.match?(LIST_MARK) }.flat_map { |run| prose(run) }
          end

          ##
          # @param lines [Array<String>, nil]
          # @param vocabulary [Vocabulary::Scope] the page language's scope, read for type chips
          # @param title [String, nil]
          # @param classifier [LinkDestination::TextClassifier] the page's label reader (memoizing within a run)
          # @return [String, nil]
          def from_lines(lines, vocabulary:, title: nil, classifier: LinkDestination::TextClassifier.for(vocabulary))
            kept = Array(lines).select { |line| keep?(line, vocabulary:, title:, classifier:) }
            kept = drop_leading_label(kept.drop_while { |line| credit?(line) })
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

          # A run of list items made of fragments reads as one prose line; real sentences stay a list.
          def prose(run)
            return run unless run.first.match?(LIST_MARK)

            items = run.map { |line| line.sub(LIST_MARK, '') }
            items.all? { |item| fragment?(item) } ? [items.join(', ')] : run
          end

          def fragment?(text) = text.length <= MAX_FRAGMENT_CHARS && !text.match?(SENTENCE_END)

          def credit?(line)
            line.length <= MAX_LABEL_CHARS && (line.match?(CREDIT_LEAD) || host_credit?(line))
          end

          def host_credit?(line)
            CHIP_SEPARATORS.any? do |sep|
              idx = line.rindex(sep)
              idx && line[(idx + sep.length)..].match?(CREDIT_HOST)
            end
          end

          # A short unpunctuated first line is a label ("Category SDK Published") once a paragraph follows it.
          def drop_leading_label(lines)
            first, *rest = lines
            return lines unless first && fragment?(first) && first.length <= MAX_LABEL_CHARS && first.match?(LABEL_SHAPE)
            return lines unless rest.any? { |line| line.length >= MIN_PARAGRAPH_CHARS }

            rest
          end

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
            widget?(normalized, classifier) ||
              (type_chips && vocabulary.type_markers.include?(key)) ||
              SECTION_NAMES.include?(key) || normalized.end_with?(':') ||
              date_shaped?(normalized) || title_echo?(key, title)
          end

          # A read-more label, call to action, share row, reading time or byline: widgets, not prose.
          def widget?(normalized, classifier)
            classifier.read_more?(normalized) || classifier.utility_chrome?(normalized) ||
              normalized.match?(READING_TIME) || !Byline.author_of(normalized).nil?
          end

          def title_echo?(key, title)
            t = title.to_s.strip.downcase
            !t.empty? && key == t
          end
        end

        ##
        # A byline line ("Von X", "by X", "<date> / by X") feeds author, not description.
        module Byline
          # A name word: capitalised, or a lowercase particle ("van", "de").
          NAME_WORD = /(?:\p{Lu}[\p{L}.'’-]*|van|von|der|de|da|di|del|la|le)/
          # One short name: a capitalised word followed by up to three name words.
          PERSON = /\p{Lu}[\p{L}.'’-]*(?:\s+#{NAME_WORD}){0,3}/
          # Function words that make a capitalised phrase prose ("By The Associated Press", "By Order of the King"),
          # never a person. Particles inside a name ("van", "von", "de") are not listed.
          FUNCTION_WORDS = %w[and or of the for in on at to with und oder die das et ou y].freeze
          # "by"/"von" are the only literal tokens (a vocabulary concept would replace them) before one person, or
          # two full names joined by "and"/"und"/"&"/",".
          PATTERN = /\A(?i:by|von)\s+(?<names>(?<first>#{PERSON})(?:\s*(?:,|&|and|und)\s+(?<second>#{PERSON}))?)\z/
          # Separator between a date and a byline on one line ("27 Nov 2026 / by Name").
          DATE_SEPARATOR = ' / '

          class << self
            ##
            # @param line [String, nil]
            # @return [String, nil] the author name when +line+ is a byline of at most {Description::MAX_LABEL_CHARS}
            def author_of(line)
              text = line.to_s.gsub(/[[:space:]]+/, ' ').strip
              return if text.length > Description::MAX_LABEL_CHARS || text.match?(Description::SENTENCE_END)

              head, sep, tail = text.rpartition(DATE_SEPARATOR)
              candidate = !sep.empty? && Description.date_shaped?(head) ? tail : text
              match = candidate.match(PATTERN)
              match[:names] if match && person_names?(match[:first], match[:second])
            end

            ##
            # @param lines [Array<String>]
            # @return [String, nil] the author of the first byline line
            def first_author(lines) = lines.filter_map { |line| author_of(line) }.first

            private

            # No function word in a name; two joined names are full names ("By Land and Sea" is prose).
            def person_names?(first, second)
              names = [first, second].compact
              names.none? { |name| name.downcase.split.intersect?(FUNCTION_WORDS) } &&
                (second.nil? || names.all? { |name| name.include?(' ') })
            end
          end
        end
      end
    end
  end
end
