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
      DATE_PIECE = /\A(?:\d{4}年)?\d{1,2}月\d{1,2}日(?:\s+#{CLOCK})?\z/
      # Content-type markers (lowercase). Description drops them as whole leftover lines.
      TYPE_MARKERS = Set[
        'news', 'news article', 'press release', 'video', 'audio', 'podcast', 'gallery', 'live', 'live blog',
        'full episode', 'bildergalerie', 'fotostrecke', 'liveticker', 'pressemitteilung', 'ganze folge',
        'vidéo', 'diaporama', 'en direct', 'communiqué de presse', 'épisode complet',
        'vídeo', 'galería', 'en directo', 'nota de prensa', 'episodio completo',
        'diretta', 'in diretta', 'diretta streaming', 'fotogallery', 'galleria', 'comunicato stampa',
        'puntata completa',
        'liveblog', 'fotogalerij', 'persbericht', 'volledige aflevering',
        'wideo', 'galeria', 'na żywo', 'relacja na żywo', 'komunikat prasowy', 'cały odcinek',
        'bildspel', 'direkt', 'direktsändning', 'liverapport', 'livesändning', 'pressmeddelande', 'hela avsnittet',
        '速報', '詳報', '独自', '動画', '写真', '中継', '生中継', 'ライブ', 'プレスリリース'
      ].freeze
      # The markers as one alternation, longest first so +live blog+ wins over +live+.
      MARKER_ALTERNATION = Regexp.union(TYPE_MARKERS.sort_by { -_1.length }).source
      # One separator between a kicker and its headline: +: | • · – — - / > » › →+, each only when
      # followed by whitespace, so a sign (+–5 Grad+), a path (+/e/+) or a German »quote« is not one, nor
      # a comparison before a number (+> 50 Prozent+).
      SEPARATOR_MARK = %r{(?:[:|•·–—/»›→-]|>(?![[:space:]]*\d))(?=[[:space:]]|\z)}
      # Screen-reader field labels (+Section:+) and type labels with their marker (+Article type: Video+).
      LABEL = /
        (?:section|category|topic|rubrik|ressort|kategorie|thema|rubrique|cat[ée]gorie|th[èe]me|secci[óo]n
          |categor[íi]a|tema|sezione|categoria|argomento|rubrica|sectie|categorie|onderwerp|rubriek
          |sekcja|kategoria|temat|dzia[łl]|sektion|kategori|[äa]mne
          |セクション|カテゴリー?|ジャンル|分類)\s*[:：]
        | (?:article\s+type|content\s+type|artikeltyp|beitragstyp|inhaltstyp|type\s+d['’]article
            |type\s+de\s+contenu|tipo\s+de\s+art[íi]culo|tipo\s+de\s+contenido
            |tipo\s+di\s+articolo|tipo\s+di\s+contenuto|artikeltype|inhoudstype|soort\s+artikel
            |typ\s+artyku[łl]u|typ\s+tre[śs]ci|rodzaj\s+tre[śs]ci|innehållstyp
            |記事の種類|記事タイプ|コンテンツの種類)\s*[:：]
          (?:\s*(?:#{MARKER_ALTERNATION})(?![[:alnum:]]))?
      /ix
      # A whole piece that is only a label: a screen-reader label element, never headline text.
      LABEL_PIECE = /\A(?:#{LABEL})\z/
      # Leading separators of a headline (+Kicker</span> – Headline+ leaves +– Headline+).
      LEADING_SEPARATORS = /\A(?:[[:space:]]|#{SEPARATOR_MARK})+/
      # A leading Japanese bracket (+【…】+ or +＜…＞+) of one to thirty characters, with headline text after it.
      LEADING_BRACKET = /\A[【＜][[:space:]]*([^】＞]{1,30}?)[[:space:]]*[】＞][[:space:]]*(?=\S)/
      # A bracket naming a content type (+【速報】+): noise as a kicker.
      BRACKET_LABEL = /[【＜][[:space:]]*(?:#{MARKER_ALTERNATION})[[:space:]]*[】＞]/i
      # Leading kicker noise, repeated: separators, separated clocks, labels.
      KICKER_NOISE = /
        \A(?:
          [[:space:]] | #{SEPARATOR_MARK} | #{LABEL} | #{BRACKET_LABEL}
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
      private_constant :MARKER_ALTERNATION, :LEADING_BRACKET, :BRACKET_LABEL, :LABEL, :LABEL_PIECE,
                       :LEADING_SEPARATORS, :KICKER_NOISE, :TRAILING_SEPARATORS, :SPACED_COLON, :TERMINAL_PUNCTUATION

      class << self
        ##
        # @param text [String, nil] title text as extracted
        # @return [String, nil] +text+ without {INVISIBLE} characters, whitespace runs (newlines included)
        #   collapsed and trimmed, or nil when blank
        def collapse(text)
          collapsed = text.to_s
          collapsed = collapsed.gsub(INVISIBLE, '') if collapsed.match?(INVISIBLE)
          collapsed = collapsed.gsub(/[[:space:]]+/, ' ').strip
          collapsed unless collapsed.empty?
        end

        ##
        # @param headline [String, nil] headline text as extracted; kept verbatim apart from separators
        # @param kicker [String, nil] kicker / eyebrow text, when the source exposes one
        # @return [String, nil] +Kicker: Headline+, the headline, the kicker when the headline is blank,
        #   or nil when both are blank
        def compose(headline, kicker: nil)
          head, top = peel_bracket(trim(headline, LEADING_SEPARATORS), trim(kicker, KICKER_NOISE))
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
        # Whether a piece of text is only a calendar date or a date with a clock time (+11月12日 16:42+).
        # {Html::TitlePieces} drops such elements at either edge of the headline.
        #
        # @param text [String, nil] visible text of one headline descendant element
        # @return [Boolean]
        def date_piece?(text) = collapse(text).to_s.match?(DATE_PIECE)

        ##
        # Whether one element inside a headline is teaser noise on its own: only a clock time or only a
        # label (+Section:+, +Article type: Video+). {Html::TitlePieces} drops such elements when they open
        # the headline; the headline text itself is never noise-stripped.
        #
        # @param text [String, nil] visible text of one headline descendant element
        # @return [Boolean]
        def headline_noise_piece?(text)
          piece = collapse(text).to_s
          piece.match?(CLOCK_PIECE) || piece.match?(DATE_PIECE) || piece.match?(LABEL_PIECE)
        end

        ##
        # Whether one child element of a kicker is noise on its own: blank, a clock time, a closed field
        # label (+Thema:+, +Section:+) or a type marker. Any other piece ending in a colon is kicker text
        # (+Conflict:+); {.compose} trims that colon. {Html::TitlePieces} drops noise kicker pieces.
        #
        # @param text [String, nil] visible text of one kicker child element
        # @return [Boolean]
        def noise_piece?(text)
          piece = collapse(text)
          piece.nil? || piece.match?(LABEL_PIECE) || piece.match?(CLOCK_PIECE) || TYPE_MARKERS.include?(piece.downcase)
        end

        private

        def trim(text, prefix)
          return unless (collapsed = collapse(text))

          trimmed = collapsed.sub(prefix, '').sub(TRAILING_SEPARATORS, '').sub(SPACED_COLON, "\\1#{SEPARATOR}")
          trimmed unless trimmed.empty?
        end

        # A leading bracket naming a content type leaves the headline; any other bracket text is the kicker
        # unless the source already gave one (then the headline stays whole).
        def peel_bracket(head, top)
          return [head, top] unless (bracket = head&.match(LEADING_BRACKET))
          return [bracket.post_match, top] if TYPE_MARKERS.include?(bracket[1].downcase)
          return [head, top] if top

          [bracket.post_match, bracket[1]]
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
