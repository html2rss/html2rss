# frozen_string_literal: true

module Html2rss
  class Article
    ##
    # Owns article title composition and the one title-noise vocabulary.
    #
    # Whitespace collapse ({.collapse}) is universal. Composition ({.compose}) is opt-in per caller
    # (see {Article#initialize}): configured selector titles and publisher feed titles stay verbatim.
    #
    # A composed title takes the form +Kicker: Headline+ (or just +Headline+, or the kicker alone when
    # the headline is blank). Both parts are whitespace-collapsed and trimmed of stray separators
    # ({SEPARATOR_MARK}). Only the kicker is noise-stripped by text: a leading clock time set off by a
    # separator (+10:00 | Topic+), screen-reader field labels (+Section:+) and type labels with their
    # marker (+Article type: Video+). The label and marker sets are small, closed and multilingual
    # (en, de, fr, es), matching {LinkDestination::TextClassifier}.
    #
    # Headline text is never noise-stripped: +20:15 Uhr: Neuer Krimi+ or +9:41 is the time+ is a real
    # headline. Teaser noise in a headline is told apart by structure instead ({Html::TitlePieces}):
    # +time+ elements and elements that are only a clock or a label ({.headline_noise_piece?}) are
    # dropped only before the first headline word, and kicker pieces are judged with {.noise_piece?}.
    module Title
      # Joins a kicker to its headline.
      SEPARATOR = ': '
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
      # Content-type markers (lowercase). Description drops them as whole leftover lines.
      TYPE_MARKERS = Set[
        'news', 'news article', 'press release', 'video', 'audio', 'podcast', 'gallery', 'live', 'live blog',
        'bildergalerie', 'fotostrecke', 'liveticker', 'pressemitteilung',
        'vidéo', 'diaporama', 'en direct', 'communiqué de presse',
        'vídeo', 'galería', 'en directo', 'nota de prensa'
      ].freeze
      # One separator between a kicker and its headline: +: | • · – — - / > » › →+, each only when
      # followed by whitespace, so a sign (+–5 Grad+), a path (+/e/+) or a German »quote« is not one, nor
      # a comparison before a number (+> 50 Prozent+).
      SEPARATOR_MARK = %r{(?:[:|•·–—/»›→-]|>(?![[:space:]]*\d))(?=[[:space:]]|\z)}
      # Screen-reader field labels (+Section:+) and type labels with their marker (+Article type: Video+).
      LABEL = /
        (?:section|category|rubrik|ressort|kategorie|rubrique|cat[ée]gorie|secci[óo]n|categor[íi]a)\s*:
        | (?:article\s+type|content\s+type|artikeltyp|beitragstyp|inhaltstyp|type\s+d['’]article
            |type\s+de\s+contenu|tipo\s+de\s+art[íi]culo|tipo\s+de\s+contenido)\s*:
          (?:\s*(?:#{Regexp.union(TYPE_MARKERS.sort_by { -_1.length }).source})(?![[:alnum:]]))?
      /ix
      # A whole piece that is only a label: a screen-reader label element, never headline text.
      LABEL_PIECE = /\A(?:#{LABEL})\z/
      # Leading separators of a headline (+Kicker</span> – Headline+ leaves +– Headline+).
      LEADING_SEPARATORS = /\A(?:[[:space:]]|#{SEPARATOR_MARK})+/
      # Leading kicker noise, repeated: separators, separated clocks, labels.
      KICKER_NOISE = /
        \A(?:
          [[:space:]] | #{SEPARATOR_MARK} | #{LABEL}
          | #{CLOCK}(?:\s*Uhr)?(?=[[:space:]]*(?:#{SEPARATOR_MARK}|\z))
        )+
      /x
      # Trailing stray separators (+Kicker :+, +Kicker -+, +Kicker ›+). A trailing +»+ closes a French
      # quote, so it stays.
      TRAILING_SEPARATORS = %r{(?:[[:space:]]|[:|•·–—]|(?<=[[:space:]])[-/>›→])+\z}
      # The inline kicker boundary of +Kicker : Headline+: a whitespace-preceded colon after at most
      # eight words ending in a letter or closing quote/bracket, so a score (+16 : 9+) keeps its colon.
      SPACED_COLON = /\A((?:[^[:space:]]+[[:space:]]+){0,7}?[^[:space:]]*[\p{L}"'“”’»›)\]])[[:space:]]+:[[:space:]]*/
      # A kicker that already ends a sentence (+Kicker?+) joins its headline with a space, not a colon.
      TERMINAL_PUNCTUATION = /[?!…‽]\z/
      private_constant :LABEL, :LABEL_PIECE, :LEADING_SEPARATORS, :KICKER_NOISE, :TRAILING_SEPARATORS,
                       :SPACED_COLON, :TERMINAL_PUNCTUATION

      class << self
        ##
        # @param text [String, nil] title text as extracted
        # @return [String, nil] +text+ with whitespace runs (newlines included) collapsed and trimmed, or nil when blank
        def collapse(text)
          collapsed = text.to_s.gsub(/[[:space:]]+/, ' ').strip
          collapsed unless collapsed.empty?
        end

        ##
        # @param headline [String, nil] headline text as extracted; kept verbatim apart from separators
        # @param kicker [String, nil] kicker / eyebrow text, when the source exposes one
        # @return [String, nil] +Kicker: Headline+, the headline, the kicker when the headline is blank,
        #   or nil when both are blank
        def compose(headline, kicker: nil)
          head = trim(headline, LEADING_SEPARATORS)
          top = trim(kicker, KICKER_NOISE)
          return head if top.nil? || noise_kicker?(top)
          return top unless head
          return head if prefixed?(head, top)

          "#{top}#{top.match?(TERMINAL_PUNCTUATION) ? ' ' : SEPARATOR}#{head}"
        end

        ##
        # Whether a piece of text is only a clock time (+19:47+, +10:00 CET+). Description peels such chips.
        #
        # @param text [String, nil] visible text of one element or chip
        # @return [Boolean]
        def clock_piece?(text) = collapse(text).to_s.match?(CLOCK_PIECE)

        ##
        # Whether one element inside a headline is teaser noise on its own: only a clock time or only a
        # label (+Section:+, +Article type: Video+). {Html::TitlePieces} drops such elements, and +time+
        # elements, when they open the headline; the headline text itself is never noise-stripped.
        #
        # @param text [String, nil] visible text of one headline descendant element
        # @return [Boolean]
        def headline_noise_piece?(text)
          piece = collapse(text).to_s
          piece.match?(CLOCK_PIECE) || piece.match?(LABEL_PIECE)
        end

        ##
        # Whether one child element of a kicker is noise on its own: blank, a clock time, a field
        # label (+Thema:+, +Section:+) or a type marker. {Html::TitlePieces} drops such kicker pieces.
        #
        # @param text [String, nil] visible text of one kicker child element
        # @return [Boolean]
        def noise_piece?(text)
          piece = collapse(text)
          piece.nil? || piece.end_with?(':') || piece.match?(CLOCK_PIECE) || TYPE_MARKERS.include?(piece.downcase)
        end

        private

        def trim(text, prefix)
          return unless (collapsed = collapse(text))

          trimmed = collapsed.sub(prefix, '').sub(TRAILING_SEPARATORS, '').sub(SPACED_COLON, "\\1#{SEPARATOR}")
          trimmed unless trimmed.empty?
        end

        def noise_kicker?(kicker) = TYPE_MARKERS.include?(kicker.downcase)

        # Whether the headline already opens with the kicker as a whole word.
        def prefixed?(head, kicker)
          head[0, kicker.length].casecmp?(kicker) && !head[kicker.length].to_s.match?(/[[:alnum:]]/)
        end
      end
    end
  end
end
