# frozen_string_literal: true

module Html2rss
  class Article
    ##
    # Owns article title composition and the one title-noise vocabulary.
    #
    # Whitespace collapse ({.collapse}) is universal and also drops invisible characters ({INVISIBLE}).
    # Composition ({.compose}) is opt-in per caller (see {Article#initialize}): configured selector titles
    # and publisher feed titles stay verbatim.
    #
    # A composed title takes the form +Kicker: Headline+ (or just +Headline+, or the kicker alone when
    # the headline is blank). Both parts are whitespace-collapsed and trimmed of stray separators
    # ({SEPARATOR_MARK}). Only the kicker is noise-stripped by text: a leading clock time set off by a
    # separator (+10:00 | Topic+), screen-reader field labels (+Section:+) and type labels with their
    # marker (+Article type: Video+). The label and marker sets are small, closed and multilingual
    # (en, de, fr, es, it, nl, pl, sv, ja), matching {LinkDestination::TextClassifier}.
    #
    # A Japanese headline may open with a bracket label (+【速報】+, +＜動画＞+): one naming a content type
    # ({TYPE_MARKERS}) is removed, any other leading bracket text becomes the kicker ({LEADING_BRACKET}).
    #
    # Pieces and kickers are matched without bidi marks ({LinkDestination::TextClassifier.strip_bidi}); the
    # title keeps its text.
    #
    # Headline text is never noise-stripped: +20:15 Uhr: Neuer Krimi+ or +9:41 is the time+ is a real
    # headline. Teaser noise in a headline is told apart by structure instead ({Html::TitlePieces}):
    # date and time elements leave wherever they sit outside running text, elements that are only a
    # clock or a label ({.headline_noise_piece?}) only before the first headline word, and kicker
    # pieces are judged with {.noise_piece?}.
    module Title
      # Joins a kicker to its headline.
      SEPARATOR = ': '
      # Characters that render nothing inside a word: soft hyphen, zero-width space, word joiner and
      # byte-order mark. Every title drops them, verbatim publisher titles included. Zero-width non-joiner
      # and joiner (U+200C, U+200D) stay: they shape Persian, Urdu and Indic spelling and join emoji.
      INVISIBLE = /[\u00AD\u200B\u2060\uFEFF]/
      # Clock time of day (24h, or 12h with AM/PM). Description chip peeling reuses it. Case-sensitive:
      # a spaced lowercase +am+ is the German preposition (+9:15 am Bahnhof+), so only +9:15am+ takes it.
      CLOCK = /(?:[01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?(?:\s*(?:AM|PM)|am|pm)?/
      # A whole piece that is only a clock time, optionally with +Uhr+ or one timezone/offset token
      # (IANA, GMT/UTC offset, or abbreviation). Description peels it as a chip suffix too.
      CLOCK_PIECE = %r{
        \A
        #{CLOCK}
        (?:\s+(?:[A-Za-z]+(?:/[A-Za-z_]+)+|(?:GMT|UTC)[+-]\d{1,2}(?::\d{2})?|[A-Za-z]{2,5}))?
        \z
      }ix
      # A whole piece that is only a Japanese calendar date (+11月12日+), optionally with a year and a clock time
      # (+11月12日 16:42+).
      DATE_PIECE = /\A(?:#{Vocabulary.alternation(:date_piece)})(?:\s+#{CLOCK})?\z/
      # The concepts a page-only language adds to the title rules, read through {Rules}.
      OWN_CONCEPTS = %i[field_label type_label clock_suffix date_piece].freeze
      # Content-type markers (lowercase). Description drops them as whole leftover lines.
      TYPE_MARKERS = Vocabulary.words(:type_marker)
      # The markers as one alternation, longest first so +live blog+ wins over +live+.
      MARKER_ALTERNATION = Regexp.union(TYPE_MARKERS.sort_by { -_1.length }).source
      # One separator between a kicker and its headline: +: | • · – — - / > » › →+, each only when
      # followed by whitespace, so a sign (+–5 Grad+), a path (+/e/+) or a German »quote« is not one, nor
      # a comparison before a number (+> 50 Prozent+).
      SEPARATOR_MARK = %r{(?:[:|•·–—/»›→-]|>(?![[:space:]]*\d))(?=[[:space:]]|\z)}
      # Leading separators of a headline (+Kicker</span> – Headline+ leaves +– Headline+).
      LEADING_SEPARATORS = /\A(?:[[:space:]]|#{SEPARATOR_MARK})+/
      # A leading Japanese bracket (+【…】+ or +＜…＞+) of one to thirty characters, with headline text after it.
      LEADING_BRACKET = /\A[【＜][[:space:]]*([^】＞]{1,30}?)[[:space:]]*[】＞][[:space:]]*(?=\S)/
      Rules = Data.define(:markers, :kicker_noise, :label_piece, :own_date_piece, :bare)

      # The page-language dependent reading of a kicker: the type markers that apply (lowercase) and the leading
      # kicker noise built on them (separators, separated clocks, screen-reader field labels (+Section:+) and
      # type labels with their marker (+Article type: Video+), a bracket naming a marker, repeated). Each field
      # label needs its colon: a bare +Article+ is a word. A letter with an accented variant is an alternation,
      # not a class: with +/i+, Ruby on Linux does not fold an uppercase accented letter (+Ä+) against a class
      # that also holds its ASCII base (+[äa]+).
      #
      # One {Rules} per distinct marker set and own-term set of {Vocabulary::SCOPES} is built at load, never per
      # page; a scope without own terms reads exactly the shared terms. Labels and type labels read every marker
      # whatever the page language: a type label (+記事の種類：独自+) is Japanese itself. The own terms of a
      # {Vocabulary::PAGE_ONLY} language widen the label, clock-suffix and date readings; +bare+ is the reading
      # without them (nil when there are none), the fallback that keeps a title from becoming empty.
      class Rules
        # @param markers [Set<String>] the type markers that apply
        # @param own [Hash{Symbol => String}] the own alternatives per {OWN_CONCEPTS}
        # @return [Rules]
        def self.build(markers, own)
          rules = assemble(markers, own)
          own.each_value.all?(&:empty?) ? rules : rules.with(bare: assemble(markers, OWN_NONE))
        end

        def self.assemble(markers, own)
          union = ->(concept) { Vocabulary.union(concept, own) }
          label = label(union)
          date = own.fetch(:date_piece)
          new(markers:, label_piece: /\A(?:#{label})\z/, bare: nil, kicker_noise: kicker_noise(label, markers, union),
              own_date_piece: (/\A(?:#{date})(?:\s+#{CLOCK})?\z/ unless date.empty?))
        end

        def self.label(union)
          /
            (?:#{union.call(:field_label)})\s*[:：]
            | (?:#{union.call(:type_label)})\s*[:：]
              (?:\s*(?:#{MARKER_ALTERNATION})(?![[:alnum:]]))?
          /ix
        end

        def self.kicker_noise(label, markers, union)
          bracket = /[【＜][[:space:]]*(?:#{Regexp.union(markers.to_a).source})[[:space:]]*[】＞]/i
          /
            \A(?:
              [[:space:]] | #{SEPARATOR_MARK} | #{label} | #{bracket}
              | #{CLOCK}(?:\s*(?:#{union.call(:clock_suffix)}))?(?=[[:space:]]*(?:#{SEPARATOR_MARK}|\z))
            )+
          /x
        end
        private_class_method :assemble, :label, :kicker_noise

        # @return [Boolean] whether the scope has own terms
        def own? = !bare.nil?
      end

      OWN_NONE = OWN_CONCEPTS.to_h { [_1, ''] }.freeze

      # The {Rules} of each page language scope, shared where the marker sets and own terms are equal.
      RULES_BY_SCOPE = Vocabulary.by_own_terms(OWN_CONCEPTS, key: :type_markers.to_proc) do |own, scope|
        Rules.build(scope.type_markers, own)
      end
      # Trailing stray separators (+Kicker :+, +Kicker -+, +Kicker ›+). A trailing +»+ closes a French
      # quote, so it stays.
      TRAILING_SEPARATORS = %r{(?:[[:space:]]|[:|•·–—]|(?<=[[:space:]])[-/>›→])+\z}
      # The inline kicker boundary of +Kicker : Headline+: a whitespace-preceded colon after at most
      # eight words ending in a letter or closing quote/bracket, so a score (+16 : 9+) keeps its colon.
      SPACED_COLON = /\A((?:[^[:space:]]+[[:space:]]+){0,7}?[^[:space:]]*[\p{L}"'“”’»›)\]])[[:space:]]+:[[:space:]]*/
      # A kicker that already ends a sentence (+Kicker?+) joins its headline with a space, not a colon.
      TERMINAL_PUNCTUATION = /[?!…‽]\z/
      private_constant :MARKER_ALTERNATION, :LEADING_BRACKET, :OWN_NONE,
                       :LEADING_SEPARATORS, :RULES_BY_SCOPE, :TRAILING_SEPARATORS, :SPACED_COLON, :TERMINAL_PUNCTUATION

      class << self
        ##
        # @param text [String, nil] title text as extracted
        # @return [String, nil] +text+ in NFC (a composed and a decomposed +Ä+ are one title) without
        #   {INVISIBLE} characters, whitespace runs (newlines included) collapsed and trimmed, or nil when blank
        def collapse(text)
          collapsed = text.to_s.unicode_normalize
          collapsed = collapsed.gsub(INVISIBLE, '') if collapsed.match?(INVISIBLE)
          collapsed = collapsed.gsub(/[[:space:]]+/, ' ').strip
          collapsed unless collapsed.empty?
        end

        ##
        # @param headline [String, nil] headline text as extracted; kept verbatim apart from separators
        # @param kicker [String, nil] kicker / eyebrow text, when the source exposes one
        # @param vocabulary [Vocabulary::Scope] the page language's scope: a Han marker that is an ordinary
        #   word of that language (+独自+ on a Chinese page) is no type marker; every marker by default
        # @return [String, nil] +Kicker: Headline+, the headline, the kicker when the headline is blank,
        #   or nil when both are blank
        def compose(headline, vocabulary:, kicker: nil)
          rules = RULES_BY_SCOPE.fetch(vocabulary.code)
          composed = join(headline, kicker, rules)
          # An own term never empties a title: without it, the kicker text would have stayed.
          composed.nil? && rules.own? ? join(headline, kicker, rules.bare) : composed
        end

        ##
        # Whether a piece of text is only a clock time (+19:47+, +10:00 CET+). Description peels such chips.
        #
        # @param text [String, nil] visible text of one element or chip
        # @return [Boolean]
        def clock_piece?(text) = read(text).to_s.match?(CLOCK_PIECE)

        ##
        # Whether a piece of text is only a calendar date or a date with a clock time (+11月12日 16:42+).
        # {Html::TitlePieces} drops such elements at either edge of the headline.
        #
        # @param text [String, nil] visible text of one headline descendant element
        # @param vocabulary [Vocabulary::Scope] the page language's scope
        # @param date_element [Boolean] whether the element is a standalone date chip (a date or time element set
        #   apart from the headline words, {Html::TitlePieces::Nodes#dropped_date?}): only there an own date term
        #   of a page-only language counts
        # @return [Boolean]
        def date_piece?(text, vocabulary:, date_element:)
          piece = read(text).to_s
          piece.match?(DATE_PIECE) || own_date_piece?(RULES_BY_SCOPE.fetch(vocabulary.code), piece, date_element)
        end

        ##
        # Whether one element inside a headline is teaser noise on its own: only a clock time or only a
        # label (+Section:+, +Article type: Video+). {Html::TitlePieces} drops such elements when they open
        # the headline; the headline text itself is never noise-stripped.
        #
        # @param text [String, nil] visible text of one headline descendant element
        # @param vocabulary [Vocabulary::Scope] the page language's scope
        # @param date_element [Boolean] whether the element is a standalone date chip (see {.date_piece?})
        # @return [Boolean]
        def headline_noise_piece?(text, vocabulary:, date_element:)
          rules = RULES_BY_SCOPE.fetch(vocabulary.code)
          piece = read(text).to_s
          shared_noise?(piece) || piece.match?(rules.label_piece) || own_date_piece?(rules, piece, date_element)
        end

        ##
        # Whether {.headline_noise_piece?} holds only through a term of a page-only language, so the caller can
        # keep the headline when dropping the element would leave it without words.
        #
        # @param text [String, nil] visible text of one headline descendant element
        # @param vocabulary [Vocabulary::Scope] the page language's scope
        # @param date_element [Boolean] whether the element is a standalone date chip (see {.date_piece?})
        # @return [Boolean]
        def own_noise_piece?(text, vocabulary:, date_element:)
          rules = RULES_BY_SCOPE.fetch(vocabulary.code)
          return false unless rules.own?

          piece = read(text).to_s
          return false if shared_noise?(piece) || piece.match?(rules.bare.label_piece)

          piece.match?(rules.label_piece) || own_date_piece?(rules, piece, date_element)
        end

        ##
        # Whether one child element of a kicker is noise on its own: blank, a clock time, a closed field
        # label (+Thema:+, +Section:+) or a type marker. Any other piece ending in a colon is kicker text
        # (+Conflict:+); {.compose} trims that colon. {Html::TitlePieces} drops noise kicker pieces.
        #
        # @param text [String, nil] visible text of one kicker child element
        # @param vocabulary [Vocabulary::Scope] the page language's scope (see {.compose})
        # @return [Boolean]
        def noise_piece?(text, vocabulary:)
          rules = RULES_BY_SCOPE.fetch(vocabulary.code)
          piece = read(text)
          piece.nil? || piece.match?(rules.label_piece) || piece.match?(CLOCK_PIECE) ||
            rules.markers.include?(piece.downcase)
        end

        private

        def join(headline, kicker, rules)
          head, top = peel_bracket(trim(headline, LEADING_SEPARATORS), trim(kicker, rules.kicker_noise), rules.markers)
          return head if top.nil? || rules.markers.include?(read(top).to_s.downcase)
          return top unless head
          return head if prefixed?(head, top)

          "#{top}#{top.match?(TERMINAL_PUNCTUATION) ? ' ' : SEPARATOR}#{head}"
        end

        def shared_noise?(piece) = piece.match?(CLOCK_PIECE) || piece.match?(DATE_PIECE)

        # An own date term counts on a standalone date chip only.
        def own_date_piece?(rules, piece, date_element)
          date_element && !rules.own_date_piece.nil? && rules.own_date_piece.match?(piece)
        end

        # The text as matching reads it: bidi marks gone first, so marks set off by spaces collapse away too
        # ({.collapse} keeps them in a title). A marks-only text reads as blank.
        def read(text) = collapse(LinkDestination::TextClassifier.strip_bidi(text.to_s))

        def trim(text, prefix)
          return unless (collapsed = collapse(text))

          trimmed = collapsed.sub(prefix, '').sub(TRAILING_SEPARATORS, '').sub(SPACED_COLON, "\\1#{SEPARATOR}")
          trimmed unless trimmed.empty?
        end

        # A leading bracket naming a content type leaves the headline; any other bracket text is the kicker
        # unless the source already gave one (then the headline stays whole).
        def peel_bracket(head, top, markers)
          return [head, top] unless (bracket = head&.match(LEADING_BRACKET))
          return [bracket.post_match, top] if markers.include?(bracket[1].downcase)
          return [head, top] if top

          [bracket.post_match, bracket[1]]
        end

        # Whether the headline already opens with the kicker as a whole word.
        def prefixed?(head, kicker)
          head[0, kicker.length].casecmp?(kicker) && !head[kicker.length].to_s.match?(/[[:alnum:]]/)
        end
      end
    end
  end
end
