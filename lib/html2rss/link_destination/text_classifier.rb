# frozen_string_literal: true

module Html2rss
  module LinkDestination
    # Classifies visible anchor text for utility, recommendation and read-more chrome. The terms are
    # {Vocabulary}'s (en, de, fr, es, it, nl, pl, sv, ja and pt); this owns how each concept is read: a whole
    # text, a prefix, a call-to-action opening, or a whole text with its topic. Utility and recommendation
    # labels honour the page language ({Vocabulary::Scope}); call-to-action and read-more labels read every
    # language.
    class TextClassifier
      # Never matches: the ambiguous matcher of a scope without ambiguous terms. Like every matcher here it is
      # fixed to UTF-8 (+/u+): a pure-ASCII regexp would be recompiled, and allocate, on each non-ASCII text.
      NEVER = /(?!)/u

      # The three label readings, as the alternatives of each scoped concept: a prefix, a whole text, a
      # recommendation. A utility label is a utility word or a recommendation label.
      READINGS = {
        utility_prefix: %i[utility_prefix],
        utility: %i[utility recommended],
        utility_label: %i[utility recommended],
        recommended: %i[recommended]
      }.freeze
      private_constant :READINGS

      # Compiles the anchored matcher of one reading from its alternatives, +NEVER+ without any. The
      # +:utility_label+ reading is a short whole text: a utility term, at most one trailing word, wrapping
      # punctuation, symbols or arrows and one bare count ("Contact us", "Comments (12)", "[Subscribe]").
      matcher = lambda do |reading, alternatives|
        alternatives = alternatives.reject(&:empty?)
        return NEVER if alternatives.empty?

        alternation = alternatives.join('|')
        return /\A\s*(#{alternation})\b/iux unless reading == :utility_label

        wrap = '[\s\p{P}\p{S}]*'
        /\A#{wrap}(?:#{alternation})(?:\s+[\p{L}\p{M}]+)?#{wrap}(?:\d+#{wrap})?\z/iux
      end

      # Per reading, the matcher of the terms every page language applies (shared, compiled once) ...
      UNAMBIGUOUS = READINGS.to_h do |reading, concepts|
        [reading, matcher.call(reading, concepts.map { Vocabulary.unambiguous_alternation(_1) })]
      end.freeze
      # ... and per scope code, the matcher of the ambiguous terms of that scope (compiled once per scope).
      AMBIGUOUS = Vocabulary::SCOPES.transform_values do |scope|
        READINGS.to_h do |reading, concepts|
          [reading, matcher.call(reading, concepts.map { scope.ambiguous_alternation(_1) })]
        end.freeze
      end.freeze
      private_constant :NEVER, :UNAMBIGUOUS, :AMBIGUOUS

      # A sentence-form call to action ("Subscribe to our newsletter", "Abonnieren Sie unseren Newsletter"): a
      # multi-word imperative phrase at the start of the text. Every phrase holds enough words that it cannot
      # open an ordinary headline, so none is scoped by page language. The word boundary after a Japanese term
      # is the script change, which +\b+ does not see between two kana or kanji.
      UTILITY_CTA = /
        \A\s*(?:#{Vocabulary.alternation(:utility_cta)})(?:\b|(?<=[\p{Han}\p{Hiragana}\p{Katakana}]))
      /iux
      private_constant :UTILITY_CTA

      # Whole read-more labels that stand alone ("Continue reading", "Lire la suite", "続きを読む").
      READ_MORE_PHRASE = /#{Vocabulary.alternation(:read_more)}/ix
      # "More about X" lead-ins: a read-more phrase or a bare "more", then a topic preposition.
      READ_MORE_TOPIC_LEAD = /
        (?:#{READ_MORE_PHRASE.source}|#{Vocabulary.alternation(:topic_lead)})
        \s+(?:#{Vocabulary.alternation(:topic_preposition)})
      /ix
      # A read-more label as a whole text, optionally wrapped in punctuation or arrows. The topic after a
      # lead-in counts only when quoted ("More about «X»", „X“, "X", 'X', 「X」), so a headline that merely
      # opens with one ("Mehr über die Zukunft der Rente") stays a headline; Japanese topic forms put the
      # topic first.
      READ_MORE_PATTERN = /
        \A[\s\p{P}\p{S}]*(?:
          (?:#{READ_MORE_PHRASE.source})|
          (?:#{READ_MORE_TOPIC_LEAD.source})\s*[«„"“”'‘’‹「].+[»"“”'’›」]|
          \S{1,40}(?:#{Vocabulary.alternation(:read_more_suffix)})
        )[\s\p{P}\p{S}]*\z
      /ix

      # Visible new-window notice that trails a link label, in parentheses or brackets.
      NEW_WINDOW_NOTICE = /
        \s*[(\[（【]\s*(?:#{Vocabulary.alternation(:new_window_notice)})\s*[)\]）】]\s*\z
      /ix

      # @param memoize [Boolean] remember normalized texts for this instance; opt in only for an instance
      #   scoped to one extraction, never for a shared constant
      # @param vocabulary [Vocabulary::Scope] the page language's scope; every ambiguous term by default
      def initialize(memoize: false, vocabulary: Vocabulary[nil])
        @normalized = {} if memoize
        @ambiguous = AMBIGUOUS.fetch(vocabulary.code)
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text matches a utility label
      def utility?(text) = label?(:utility, text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when the whole text is a utility term with at most one more word, bare or with
      #   a count; a headline that merely opens with a utility word is not
      def utility_label?(text) = label?(:utility_label, text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text opens with a call-to-action phrase, whatever follows it
      def utility_cta?(text) = normalize(text).match?(UTILITY_CTA)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text begins with a utility label
      def utility_prefix?(text) = label?(:utility_prefix, text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text identifies recommendation chrome
      def recommended?(text) = label?(:recommended, text)

      # @param text [String, #to_s] visible anchor text or extracted title
      # @return [Boolean] true when the whole text is a read-more label, bare or with its topic
      def read_more?(text) = normalize(text).match?(READ_MORE_PATTERN)

      private

      # An unambiguous term always applies; an ambiguous one only in the page's language scope.
      def label?(reading, text)
        normalized = normalize(text)
        normalized.match?(UNAMBIGUOUS.fetch(reading)) || normalized.match?(@ambiguous.fetch(reading))
      end

      # Every label is read in NFC, so a decomposed accent matches the precomposed vocabulary, and without
      # its trailing new-window notice ("(opens in new tab)").
      def normalize(text)
        string = text.to_s
        return compute_normal(string) unless @normalized

        @normalized[string] ||= compute_normal(string)
      end

      def compute_normal(string) = string.unicode_normalize(:nfc).sub(NEW_WINDOW_NOTICE, '')
    end
  end
end
