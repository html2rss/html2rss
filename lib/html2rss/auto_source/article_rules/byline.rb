# frozen_string_literal: true

module Html2rss
  class AutoSource
    module ArticleRules
      ##
      # A byline line ("Von X", "by X", "<date> / by X") feeds author, not description.
      module Byline
        # Longest line that reads as a byline.
        MAX_CHARS = 60
        # Closing punctuation of a sentence or lead-in; a byline never ends like one.
        SENTENCE_END = /[.!?…:]\z/
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
          # @return [String, nil] the author name when +line+ is a byline of at most {MAX_CHARS}
          def author_of(line)
            text = line.to_s.gsub(/[[:space:]]+/, ' ').strip
            return if text.length > MAX_CHARS || text.match?(SENTENCE_END)

            head, sep, tail = text.rpartition(DATE_SEPARATOR)
            candidate = !sep.empty? && Date.date_shaped?(head) ? tail : text
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
