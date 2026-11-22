# frozen_string_literal: true

module Html2rss
  ##
  # The closed, internal vocabulary of human-language terms the heuristics read: path words, label text,
  # read-more phrases, type markers, pager nouns. It owns the terms and one compiler; every decision (junk,
  # score, kind) stays in the module that reads the term.
  #
  # One frozen file per language ({ALL}), each mapping every concept in {CONCEPTS} to its terms or {NONE}.
  # A concept is read in one of two ways:
  #
  # - a *word* concept ({WORD_CONCEPTS}) holds exact strings, read through {.words} (path segments, type
  #   markers);
  # - a *pattern* concept ({PATTERN_CONCEPTS}) holds terms compiled once at load into a regex alternation, read
  #   through {.alternation}. A String term is a literal: escaped, with each space matching +\s++. A flagless
  #   Regexp term is a fragment, taken as written, for terms that are not literals (optional words,
  #   up-to-five-word sponsor names, a letter with an accented variant). Both are interpolated under +/i+ and
  #   +/x+ by the owner of the concept, so a fragment writes +\s+ and +\#+, never a bare space or +#+.
  #
  # A letter with an accented variant is an explicit pair of terms or a fragment alternation, never a class:
  # with +/i+, Ruby on Linux does not fold an uppercase accented letter against a class that also holds its
  # ASCII base. Accent and whitespace tolerance differ per term today, so nothing is folded or widened here.
  #
  # Words that are not language vocabulary live in {NonTranslated}; class/id tokens in {CssTokens}.
  module Vocabulary
    # A concept a language does not use. Explicit, so a missing concept is an error and an empty one is not.
    NONE = [].freeze

    # Concepts read as exact strings.
    WORD_CONCEPTS = %i[
      path_section path_article path_profile path_office path_non_article path_taxonomy path_vanity
      path_soft_utility path_chrome path_media path_deep_post_context type_marker
    ].freeze

    # Concepts read as a compiled regex alternation.
    PATTERN_CONCEPTS = %i[
      utility_prefix utility recommended read_more topic_lead topic_preposition read_more_suffix
      new_window_notice paid_label ad_word field_label type_label pager_label page_link clock_suffix
      date_piece element_label
    ].freeze

    # Every concept each language in {ALL} declares.
    CONCEPTS = (WORD_CONCEPTS + PATTERN_CONCEPTS).freeze

    # The languages, in a fixed order. Portuguese holds only the forms that exist today.
    ALL = [En, De, Fr, Es, It, Nl, Pl, Sv, Ja, Pt].freeze

    class << self
      ##
      # @param concept [Symbol] a member of {WORD_CONCEPTS}
      # @return [Set<String>] the exact terms of all languages
      def words(concept) = WORDS.fetch(concept)

      ##
      # @param concept [Symbol] a member of {PATTERN_CONCEPTS}
      # @return [String] the terms of all languages as regex alternatives, ready to interpolate
      def alternation(concept) = ALTERNATIONS.fetch(concept)

      ##
      # Compiles terms into regex alternatives: a String is a literal (escaped, each space matching a
      # whitespace run), a Regexp is a fragment taken as written.
      #
      # @param terms [Array<String, Regexp>]
      # @return [String] the alternatives joined with +|+
      def compile(terms)
        terms.map do |term|
          case term
          in Regexp then term.source
          in String then term.split.map { Regexp.escape(_1) }.join('\s+')
          end
        end.join('|').freeze
      end
    end

    WORDS = WORD_CONCEPTS.to_h do |concept|
      [concept, Set.new(ALL.flat_map { _1.terms.fetch(concept) }).freeze]
    end.freeze
    ALTERNATIONS = PATTERN_CONCEPTS.to_h do |concept|
      [concept, compile(ALL.flat_map { _1.terms.fetch(concept) })]
    end.freeze
    private_constant :WORDS, :ALTERNATIONS
  end
end
