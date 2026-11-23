# frozen_string_literal: true

module Html2rss
  module Vocabulary
    Scope = Data.define(:code, :ambiguous_words, :alternations, :own_words, :own_alternations, :type_markers)

    # What one page language reads (see {Vocabulary.[]}): the unambiguous terms of every language plus the
    # ambiguous terms of this language, or of all of them for the +:all+ scope. One frozen instance per scope;
    # it keeps only its own ambiguous terms, the unambiguous ones are shared. A {Vocabulary::PAGE_ONLY} language adds
    # its own terms, read as whole labels only (+own_words+, +own_alternations+). +type_markers+ is the set of title
    # type markers that apply: every language's markers, less (for a Chinese page) the Han ones that are ordinary
    # Chinese words; the shared +Vocabulary.words(:type_marker)+ itself when nothing is left out.
    class Scope
      # The words that apply, built per call: read once at load by the owner of a concept, never per page.
      #
      # @param concept [Symbol] a member of {Vocabulary::SCOPED_WORDS}
      # @return [Set<String>] the exact terms that apply; the shared unambiguous Set itself when none is added
      def words(concept)
        extra = ambiguous_words.fetch(concept) + own_words.fetch(concept)
        shared = Vocabulary.unambiguous_words(concept)
        extra.empty? ? shared : (shared | extra).freeze
      end

      # @param concept [Symbol] a member of {Vocabulary::SCOPED_PATTERNS}
      # @return [String] regex alternatives of the ambiguous terms that apply, empty when none
      def ambiguous_alternation(concept) = alternations.fetch(concept)

      # @param concept [Symbol] a member of {Vocabulary::SCOPED_PATTERNS} or {Vocabulary::PAGE_PATTERNS}
      # @return [String] regex alternatives of the terms only a page in this language applies, empty when none
      def own_alternation(concept) = own_alternations.fetch(concept)

      # @return [Boolean] whether a page-only language adds terms to this scope
      def own?
        own_alternations.each_value { return true unless _1.empty? }
        false
      end
    end
  end
end
