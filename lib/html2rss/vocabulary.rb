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
  #
  # == Page language
  #
  # A term a language lists under {Language#ambiguous} is also a common word or name outside its chrome
  # meaning ("dela" is a Swedish share label and a surname). Only the *scoped* concepts ({SCOPED_WORDS},
  # {SCOPED_PATTERNS}) honour it: an unambiguous term always applies; an ambiguous one applies only when its
  # language is in scope. {.[]} turns a page's language into one of the shared, frozen {Scope}s; the table is
  # closed, so a page can never add an entry. Every other concept reads all languages.
  module Vocabulary
    # A concept a language does not use. Explicit, so a missing concept is an error and an empty one is not. Every
    # human-language concept has terms in every language in {ALL}; the cells that may be NONE are listed in the
    # conformance spec: the suffix reading (only Japanese has it) and the topic lead-ins (Japanese has none),
    # +page_link+ (English only), and a clock suffix, a date piece and an element label (one language each).
    NONE = [].freeze

    # Concepts read as exact strings.
    WORD_CONCEPTS = %i[
      path_section path_article path_profile path_office path_non_article path_taxonomy path_vanity
      path_soft_utility path_chrome path_media path_deep_post_context type_marker
    ].freeze

    # Concepts read as a compiled regex alternation.
    # +page_link_label+ holds the previous/next/older/newer words of the other languages, read as a whole label;
    # +page_link+ stays the English pattern, which accepts text after the word.
    PATTERN_CONCEPTS = %i[
      utility_prefix utility recommended utility_cta read_more topic_lead topic_preposition read_more_suffix
      new_window_notice paid_label ad_word field_label type_label pager_label page_link page_link_label
      clock_suffix date_piece element_label podcast_word podcast_unspaced
    ].freeze

    # Word concepts that honour {Language#ambiguous} (the path words; type markers read every language).
    SCOPED_WORDS = (WORD_CONCEPTS - %i[type_marker]).freeze

    # Pattern concepts that honour {Language#ambiguous}.
    SCOPED_PATTERNS = %i[utility_prefix utility recommended].freeze

    # Pattern concepts a {PAGE_ONLY} language may declare besides {SCOPED_PATTERNS}: the call-to-action, read-more
    # and new-window readers of {LinkDestination::TextClassifier}, the sponsorship labels of
    # {LinkDestination::Sponsorship::LabelText}, the title concepts of {Article::Title} and the pager concepts of
    # {SST::Tags}, which read a scope's own terms as whole labels. The podcast concepts stay out: their reader
    # matches inside URLs and titles, where a short Han term is not precise. A concept joins this list only when
    # every production path that reads it takes the page scope; a page-only language declaring any other pattern
    # concept would have a dead term, so the conformance spec rejects it.
    PAGE_PATTERNS = %i[utility_cta read_more topic_lead topic_preposition read_more_suffix new_window_notice
                       paid_label ad_word element_label field_label type_label clock_suffix date_piece
                       pager_label page_link page_link_label].freeze

    # Every concept each language in {ALL} declares.
    CONCEPTS = (WORD_CONCEPTS + PATTERN_CONCEPTS).freeze

    # The languages, in a fixed order.
    ALL = [En, De, Fr, Es, It, Nl, Pl, Sv, Ja, Pt, Ru].freeze

    # Languages whose terms apply only on a page in that language: they are in no shared table, so +:all+, +ja+ and
    # every other language read exactly what they read without them. A page scope of such a language is +:all+ plus
    # its terms (a Han term has no word boundary, so it is read as a whole label only, see {TextClassifier}).
    PAGE_ONLY = [Zh, Ko, He, El, Uk, Ar, Fa, Hi, Th, Tr, Id, Vi, Cs, Hu, Da].freeze

    # Every language that has a file, in a fixed order.
    LANGUAGES = (ALL + PAGE_ONLY).freeze

    # A language tag: a primary subtag, then region/script subtags (+de+, +de-AT+, +zh_Hant_TW+).
    TAG = /\A([a-z]{2,3})(?:[-_][a-z0-9]{1,8})*\z/i

    class << self
      ##
      # The scope of one page language: the terms that apply to it. Regional tags reduce to the primary tag
      # (+de-AT+ and +zh-Hant+ are +de+ and +zh+), case-insensitively; nil, blank, malformed and unsupported values
      # are the +all+ scope, where every ambiguous term applies.
      #
      # @param lang [String, Symbol, nil] the page language, as {Html2rss::Channel} resolves it
      # @return [Scope] one of the {SCOPES}; the identical frozen object on every call
      def [](lang)
        case lang
        in String | Symbol then BY_TAG.fetch(lang) { BY_TAG.fetch(lang.to_s.strip[TAG, 1]&.downcase, ALL_SCOPE) }
        else ALL_SCOPE
        end
      end

      ##
      # @param concept [Symbol] a member of {WORD_CONCEPTS} that is not in {SCOPED_WORDS} (those are read
      #   through a {Scope})
      # @return [Set<String>] the exact terms of all languages
      def words(concept) = WORDS.fetch(concept)

      ##
      # @param concept [Symbol] a member of {PATTERN_CONCEPTS} that is not in {SCOPED_PATTERNS} (those are
      #   read through {.unambiguous_alternation} and a {Scope})
      # @return [String] the terms of all languages as regex alternatives, ready to interpolate
      def alternation(concept) = ALTERNATIONS.fetch(concept)

      ##
      # @param concept [Symbol] a member of {SCOPED_WORDS}
      # @return [Set<String>] the exact terms every language applies, whatever the page language
      def unambiguous_words(concept) = UNAMBIGUOUS_WORDS.fetch(concept)

      ##
      # @param concept [Symbol] a member of {SCOPED_PATTERNS}
      # @return [String] the alternatives every language applies, whatever the page language
      def unambiguous_alternation(concept) = UNAMBIGUOUS_ALTERNATIONS.fetch(concept)

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

      ##
      # @param languages [Array<Language>] the languages in scope
      # @param concept [Symbol] a member of {SCOPED_WORDS} or {SCOPED_PATTERNS}
      # @return [Array<String, Regexp>] the terms those languages flag as ambiguous for the concept
      def ambiguous_terms(languages, concept) = languages.flat_map { _1.ambiguous.fetch(concept, NONE) }.uniq.freeze

      ##
      # The shared terms of every language for a {PAGE_PATTERNS} concept, widened by a scope's own terms.
      #
      # @param concept [Symbol] a member of {PAGE_PATTERNS}
      # @param own [Hash{Symbol => String}] a scope's own alternatives per concept ({Scope#own_alternation})
      # @return [String] regex alternatives, the shared ones when there are no own terms
      def union(concept, own) = [alternation(concept), own.fetch(concept)].reject(&:empty?).join('|')

      ##
      # The one owner of the per-scope reading tables of the page-only concepts: builds one entry per distinct own-term
      # set (and +key+, when the entry also depends on something else of the scope) at load, so every scope without
      # own terms shares one entry and nothing is compiled per page.
      #
      # @param concepts [Array<Symbol>] the {PAGE_PATTERNS} concepts the reader takes own terms of
      # @param key [#call, nil] maps a scope to the other fact its entry depends on
      # @yieldparam own [Hash{Symbol => String}] the scope's own alternatives per concept
      # @yieldparam scope [Scope]
      # @yieldreturn [Object] the entry
      # @return [Hash{Symbol => Object}] the entry of each scope code
      def by_own_terms(concepts, key: nil)
        built = {}
        SCOPES.transform_values do |scope|
          own = concepts.to_h { [_1, scope.own_alternation(_1)] }
          built[[key&.call(scope), own]] ||= yield(own, scope)
        end.freeze
      end

      ##
      # Builds a scope, which keeps only its ambiguous terms (a few per concept); the unambiguous ones are shared.
      #
      # @param code [Symbol] the language code, or +:all+
      # @param languages [Array<Language>] the languages in scope
      # @param own [Array<Language>] {PAGE_ONLY} languages whose terms apply on this page only
      # @return [Scope]
      def build_scope(code, languages, own: [])
        words = SCOPED_WORDS.to_h { [_1, ambiguous_terms(languages, _1)] }
        alternations = SCOPED_PATTERNS.to_h { [_1, compile(ambiguous_terms(languages, _1))] }
        Scope.new(code:, ambiguous_words: words.freeze, alternations: alternations.freeze,
                  own_words: own_terms(own, SCOPED_WORDS), own_alternations: own_alternations(own),
                  type_markers: type_markers_for(own))
      end

      private

      def own_terms(own, concepts) = concepts.to_h { |c| [c, own.flat_map { _1.terms.fetch(c) }.freeze] }.freeze

      def own_alternations(own)
        own_terms(own, SCOPED_PATTERNS + PAGE_PATTERNS).transform_values { compile(_1) }.freeze
      end

      ##
      # @param own [Array<Language>] the {PAGE_ONLY} languages of the scope
      # @return [Set<String>] the title type markers that apply: every language's, less the {Language#plain_words}
      #   of the own languages and plus their own markers; the shared +words(:type_marker)+ itself without any
      def type_markers_for(own)
        return words(:type_marker) if own.empty?

        plain = own.flat_map { _1.plain_words.to_a }
        marked = own.flat_map { _1.terms.fetch(:type_marker) }
        (words(:type_marker) - plain).union(marked).freeze
      end
    end

    WORDS = (WORD_CONCEPTS - SCOPED_WORDS).to_h do |concept|
      [concept, Set.new(ALL.flat_map { _1.terms.fetch(concept) }).freeze]
    end.freeze
    ALTERNATIONS = (PATTERN_CONCEPTS - SCOPED_PATTERNS).to_h do |concept|
      [concept, compile(ALL.flat_map { _1.terms.fetch(concept) })]
    end.freeze

    UNAMBIGUOUS_WORDS = SCOPED_WORDS.to_h do |concept|
      terms = ALL.flat_map { _1.terms.fetch(concept) } - ambiguous_terms(ALL, concept)
      [concept, Set.new(terms).freeze]
    end.freeze
    UNAMBIGUOUS_ALTERNATIONS = SCOPED_PATTERNS.to_h do |concept|
      [concept, compile(ALL.flat_map { _1.terms.fetch(concept) } - ambiguous_terms(ALL, concept))]
    end.freeze

    # One shared, frozen scope per language in {ALL}, plus +:all+ (every ambiguous term applies) and one per {PAGE_ONLY}
    # language: +:all+ plus that language's own terms.
    SCOPES = ALL.to_h { [_1.code, build_scope(_1.code, [_1])] }
                .merge(all: build_scope(:all, ALL))
                .merge(PAGE_ONLY.to_h { [_1.code, build_scope(_1.code, ALL, own: [_1])] }).freeze
    ALL_SCOPE = SCOPES.fetch(:all)
    # Every accepted primary tag, as a String or a Symbol, so the usual lookup allocates nothing.
    BY_TAG = SCOPES.except(:all).flat_map { |code, scope| [[code, scope], [code.name, scope]] }.to_h.freeze
    private_constant :TAG, :WORDS, :ALTERNATIONS, :UNAMBIGUOUS_WORDS, :UNAMBIGUOUS_ALTERNATIONS, :BY_TAG, :ALL_SCOPE
  end
end
