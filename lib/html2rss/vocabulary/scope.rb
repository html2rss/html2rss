# frozen_string_literal: true

module Html2rss
  module Vocabulary
    Scope = Data.define(:code, :ambiguous_words, :alternations)

    # What one page language reads (see {Vocabulary.[]}): the unambiguous terms of every language plus the
    # ambiguous terms of this language, or of all of them for the +:all+ scope. One frozen instance per scope;
    # it keeps only its own ambiguous terms, the unambiguous ones are shared.
    class Scope
      # The words that apply, built per call: read once at load by the owner of a concept, never per page.
      #
      # @param concept [Symbol] a member of {Vocabulary::SCOPED_WORDS}
      # @return [Set<String>] the exact terms that apply; the shared unambiguous Set itself when none is added
      def words(concept)
        extra = ambiguous_words.fetch(concept)
        shared = Vocabulary.unambiguous_words(concept)
        extra.empty? ? shared : (shared | extra).freeze
      end

      # @param concept [Symbol] a member of {Vocabulary::SCOPED_PATTERNS}
      # @return [String] regex alternatives of the ambiguous terms that apply, empty when none
      def ambiguous_alternation(concept) = alternations.fetch(concept)
    end
  end
end
