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
        # A whole-line reading time ("3 Min", "5 Minuten", "4 minutes read").
        READING_TIME = /\A\d{1,3}\s?(?:min(?:\.|uten|utes?)?)(?:\s(?:read|lesezeit))?\z/i
        # A short leading line that opens with a photo-credit label.
        CREDIT_LEAD = /\A(?:©|(?:foto|photo|bild)\s?:)/i
        # A host name such as "example.com" closing a credit line ("Name – example.com").
        CREDIT_HOST = /\A\p{L}[\p{L}\d-]{0,30}(?:\.[\p{L}\d-]{1,30}){0,3}\.\p{L}{2,12}\z/
        # Longest line that counts as a credit or a label rather than prose.
        MAX_LABEL_CHARS = 60
        # One to four words within {MAX_LABEL_CHARS}, as a leading label holds ("Category SDK Published").
        LABEL_SHAPE = /\A(?=.{1,#{MAX_LABEL_CHARS}}\z)\S+(?:\s\S+){0,3}\z/
        # A line must be at least this long to count as the paragraph a leading label belongs to.
        MIN_PARAGRAPH_CHARS = 40
        # List markup prefix the text reader puts on list items.
        LIST_MARK = /\A- /
        # An item of this length without sentence-ending punctuation is a fragment, not a sentence.
        MAX_FRAGMENT_CHARS = 40

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

          private

          def normalize(line) = line.to_s.gsub(/[[:space:]]+/, ' ').strip

          # A run of list items made of fragments reads as one prose line; real sentences stay a list.
          def prose(run)
            return run unless run.first.match?(LIST_MARK)

            items = run.map { |line| line.sub(LIST_MARK, '') }
            items.all? { |item| fragment?(item) } ? [items.join(', ')] : run
          end

          def fragment?(text) = text.length <= MAX_FRAGMENT_CHARS && !text.match?(Byline::SENTENCE_END)

          def credit?(line)
            line.length <= MAX_LABEL_CHARS && (line.match?(CREDIT_LEAD) || host_credit?(line))
          end

          def host_credit?(line)
            Date::CHIP_SEPARATORS.any? do |sep|
              idx = line.rindex(sep)
              idx && line[(idx + sep.length)..].match?(CREDIT_HOST)
            end
          end

          # A short unpunctuated first line is a label ("Category SDK Published") once a paragraph follows it.
          def drop_leading_label(lines)
            first, *rest = lines
            return lines unless first && fragment?(first) && first.match?(LABEL_SHAPE)
            return lines unless rest.any? { |line| line.length >= MIN_PARAGRAPH_CHARS }

            rest
          end

          def chrome?(normalized, vocabulary, title:, type_chips:, classifier:)
            key = normalized.downcase
            widget?(normalized, classifier) ||
              (type_chips && vocabulary.type_markers.include?(key)) ||
              SECTION_NAMES.include?(key) || normalized.end_with?(':') ||
              Date.date_shaped?(normalized) || title_echo?(key, title)
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
      end
    end
  end
end
