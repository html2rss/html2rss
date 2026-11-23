# frozen_string_literal: true

module Html2rss
  module Vocabulary
    Language = Data.define(:code, :terms, :ambiguous, :plain_words, :latin)

    # One language: its code, its terms per concept (see {Vocabulary::CONCEPTS}) and, per scoped concept, the
    # terms that are also a common word or name outside the language's chrome meaning. An ambiguous term stays
    # in +terms+ and is repeated in +ambiguous+; it applies only when the page is in this language. A language
    # without ambiguous terms declares none. +plain_words+ are shared title type markers that are ordinary words on
    # a page in this language, so a {Vocabulary::PAGE_ONLY} language's scope reads them as text, not as markers.
    # Every other scope keeps the full marker set. +latin+ marks a {Vocabulary::PAGE_ONLY} language written in Latin
    # script: its scope reads no foreign ambiguous term, because on a Latin page one can be an ordinary word.
    class Language
      # @param code [Symbol]
      # @param terms [Hash{Symbol => Array<String, Regexp>}]
      # @param ambiguous [Hash{Symbol => Array<String, Regexp>}]
      # @param plain_words [Set<String>] shared type markers that are no marker on this language's pages
      # @param latin [Boolean] whether a page-only language is written in Latin script
      def initialize(code:, terms:, ambiguous: {}.freeze, plain_words: Set.new.freeze, latin: false) = super
    end
  end
end
