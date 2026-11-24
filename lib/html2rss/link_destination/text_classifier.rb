# frozen_string_literal: true

module Html2rss
  module LinkDestination
    # Classifies visible anchor text for utility, recommendation and read-more chrome. The terms are
    # {Vocabulary}'s (every language in {Vocabulary::LANGUAGES}); this owns how each concept is read: a whole
    # text, a prefix, a call-to-action opening, or a whole text with its topic. Utility and recommendation
    # labels honour the page language ({Vocabulary::Scope}); call-to-action and read-more labels read every
    # language of {Vocabulary::SHARED_LANGUAGES}. A {Vocabulary::PAGE_ONLY} language's terms are read as whole
    # labels only.
    class TextClassifier
      # Never matches: the ambiguous matcher of a scope without ambiguous terms. Like every matcher here it is
      # fixed to UTF-8 (+/u+): a pure-ASCII regexp would be recompiled, and allocate, on each non-ASCII text.
      NEVER = /(?!)/u

      # Direction marks and embedding/isolate controls (LRM, RLM, ALM, LRE..RLO, LRI..PDI): they render nothing and
      # change no letter, so a label ("\u200FContact\u200F") is read without them ({.strip_bidi}). Only the
      # label text is read this way; extracted titles and descriptions keep them.
      BIDI_MARKS = /[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]/

      # The three label readings, as the alternatives of each scoped concept: a prefix, a whole text, a
      # recommendation. A utility label is a utility word or a recommendation label.
      READINGS = {
        utility_prefix: %i[utility_prefix],
        utility: %i[utility recommended],
        utility_label: %i[utility recommended],
        recommended: %i[recommended]
      }.freeze

      class << self
        ##
        # The shared, non-memoizing classifier of a page language's scope: nothing is built per call.
        #
        # @param vocabulary [Vocabulary::Scope] the page language's scope ({Vocabulary.[]})
        # @return [TextClassifier]
        def for(vocabulary) = SHARED.fetch(vocabulary.code)

        # The one owner of reading a label without direction marks ({BIDI_MARKS}). Text without a mark is
        # returned as is, so the common case allocates nothing.
        #
        # @param text [String]
        # @return [String] +text+ without bidi marks
        def strip_bidi(text) = text.match?(BIDI_MARKS) ? text.gsub(BIDI_MARKS, '') : text

        ##
        # Compiles the anchored matcher of one reading from its alternatives, +NEVER+ without any. The
        # +:utility_label+ reading is a short whole text: a utility term, at most one trailing word, wrapping
        # punctuation, symbols or arrows and one bare count ("Contact us", "Comments (12)", "[Subscribe]").
        # The one owner of how a label term is read, so a spec reads a single term exactly as a page does.
        #
        # @param reading [Symbol] a key of {READINGS}
        # @param alternatives [Array<String>] regex alternatives (see {Vocabulary.compile})
        # @return [Regexp]
        def matcher(reading, alternatives)
          alternatives = alternatives.reject(&:empty?)
          return NEVER if alternatives.empty?

          alternation = alternatives.join('|')
          return /\A\s*(#{alternation})\b/iux unless reading == :utility_label

          wrap = '[\s\p{P}\p{S}]*'
          /\A#{wrap}(?:#{alternation})(?:\s+[\p{L}\p{M}]+)?#{wrap}(?:\d+#{wrap})?\z/iux
        end

        # @param alternatives [Array<String>] regex alternatives of a scope's own terms
        # @return [Regexp] the whole text is one term, with wrapping punctuation, symbols or arrows and one short
        #   count inside matching brackets (+(3)+, +[3]+, +（3）+, +［3］+, up to three digits), and no other word: a
        #   bare trailing number (a year, a numbered column) means the text is no label; +NEVER+ without any
        #   alternative
        def whole_label(alternatives)
          alternatives = alternatives.reject(&:empty?)
          return NEVER if alternatives.empty?

          wrap = '[\s\p{P}\p{S}]*'
          /\A#{wrap}(?:#{alternatives.join('|')})#{wrap}(?:#{BRACKETED_COUNT}#{wrap})?\z/iux
        end
      end

      # A count of up to three digits inside matching brackets; an unbalanced bracket is no count.
      BRACKETED_COUNT = '(?:\(\s*\d{1,3}\s*\)|\[\s*\d{1,3}\s*\]|（\s*\d{1,3}\s*）|［\s*\d{1,3}\s*］)'

      # Per reading, the matcher of the terms every page language applies (shared, compiled once) ...
      UNAMBIGUOUS = READINGS.to_h do |reading, concepts|
        [reading, matcher(reading, concepts.map { Vocabulary.unambiguous_alternation(_1) })]
      end.freeze
      # ... per scope code, the matcher of the ambiguous terms of that scope (compiled once per distinct
      # alternatives) ...
      AMBIGUOUS = begin
        built = {}
        Vocabulary::SCOPES.transform_values do |scope|
          built[scope.alternations] ||= READINGS.to_h do |reading, concepts|
            [reading, matcher(reading, concepts.map { scope.ambiguous_alternation(_1) })]
          end.freeze
        end.freeze
      end
      # ... and, for a scope with terms of its own ({Vocabulary::PAGE_ONLY}), the whole-label matcher of those terms
      # (+NEVER+ for any other scope) for every reading: no trailing word and no headline opener, because a Han
      # term has no word boundary.
      OWN = Vocabulary.by_own_terms(Vocabulary::SCOPED_PATTERNS) do |own, _|
        READINGS.transform_values { whole_label(own.values_at(*_1)) }.freeze
      end
      private_constant :NEVER, :BIDI_MARKS, :BRACKETED_COUNT, :UNAMBIGUOUS, :AMBIGUOUS, :OWN

      # Zero-width non-joiner and joiner. Inside a word they spell Persian, Urdu and Indic words, so a label
      # holding one is trimmed only at its edges, up to the first and last {LABEL_CHAR}.
      JOINER = /[\u200C\u200D]/
      LABEL_CHAR = /[^\s\u200C\u200D]/
      private_constant :JOINER, :LABEL_CHAR

      # @param memoize [Boolean] remember normalized texts and read-more verdicts for this instance; opt in only
      #   for an instance scoped to one extraction, never for a shared constant
      # @param vocabulary [Vocabulary::Scope] the page language's scope; every ambiguous term by default
      def initialize(memoize: false, vocabulary: Vocabulary[nil])
        @normalized = {} if memoize
        @read_more = {} if memoize
        @ambiguous = AMBIGUOUS.fetch(vocabulary.code)
        @own = OWN.fetch(vocabulary.code)
        @page = PageReadings::BY_SCOPE.fetch(vocabulary.code)
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text matches a utility label
      def utility?(text) = label?(:utility, text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when the text is utility chrome: a short whole label (a utility term with at most
      #   one more word, bare or with a count) or a sentence-form call to action ("Subscribe to our newsletter");
      #   a headline that merely opens with a utility word is neither. The text is normalized once.
      def utility_chrome?(text)
        normalized = normalize(text)
        reading_match?(:utility_label, normalized) ||
          normalized.match?(@page.fetch(:cta)) || normalized.match?(@page.fetch(:own_cta))
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when {#utility_chrome?} holds only through a term of the page-only language of
      #   this scope: no other language reads the text as chrome, so an ordinary noun of that language
      #   ("评论" is also "comment") may be a card's only link; false for every shared language scope
      def page_only_chrome?(text)
        utility_chrome?(text) && !SHARED.fetch(:all).utility_chrome?(text)
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text begins with a utility label
      def utility_prefix?(text) = label?(:utility_prefix, text)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text identifies recommendation chrome
      def recommended?(text) = label?(:recommended, text)

      # @param text [String, #to_s] visible anchor text or extracted title
      # @return [Boolean] true when the whole text is a read-more label, bare or with its topic, or an own read-more
      #   or list-level term of a page-only language with a short bracketed count (+Xem tất cả [3]+)
      def read_more?(text)
        normalized = normalize(text)
        return read_more_label?(normalized) unless @read_more

        @read_more.fetch(normalized) { @read_more[normalized] = read_more_label?(normalized) }
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when the whole text is a list-level "more" or "see all" term of a page-only language,
      #   bare or with a bracketed count; always false on a scope without own terms
      def list_more?(text) = normalize(text).match?(@page.fetch(:list_more))

      private

      def read_more_label?(normalized)
        normalized.match?(@page.fetch(:read_more)) || normalized.match?(@page.fetch(:own_more))
      end

      def label?(reading, text) = reading_match?(reading, normalize(text))

      # An unambiguous term always applies; an ambiguous one only in the page's language scope, and a term of
      # the scope's own language as a whole label.
      def reading_match?(reading, normalized)
        normalized.match?(UNAMBIGUOUS.fetch(reading)) || normalized.match?(@ambiguous.fetch(reading)) ||
          normalized.match?(@own.fetch(reading))
      end

      # Every label is read in NFC, so a decomposed accent matches the precomposed vocabulary, without bidi
      # marks ({BIDI_MARKS}), without its trailing new-window notice ("(opens in new tab)") and without
      # joiners at its edges ({JOINER}).
      def normalize(text)
        string = text.to_s
        return compute_normal(string) unless @normalized

        @normalized[string] ||= compute_normal(string)
      end

      def compute_normal(string)
        text = string.ascii_only? ? string : string.unicode_normalize(:nfc)
        text = self.class.strip_bidi(text).sub(@page.fetch(:new_window), '')
        text.match?(JOINER) ? trim_edges(text) : text
      end

      def trim_edges(text) = text[text.index(LABEL_CHAR)..text.rindex(LABEL_CHAR)]

      # One classifier per scope, built after the class body so every constant it reads exists.
      SHARED = Vocabulary::SCOPES.transform_values { new(vocabulary: _1) }.freeze
      private_constant :SHARED
    end
  end
end
