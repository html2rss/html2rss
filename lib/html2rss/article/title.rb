# frozen_string_literal: true

module Html2rss
  class Article
    ##
    # Owns article title composition and the one title-noise vocabulary.
    #
    # Whitespace collapse ({.collapse}) is universal. Composition ({.compose}) is opt-in per caller
    # (see {Article#initialize}): configured selector titles and publisher feed titles stay verbatim.
    #
    # A composed title takes the form +Kicker: Headline+ (or just +Headline+). Both parts are
    # whitespace-collapsed, trimmed of stray separators, and stripped of leading noise: a clock
    # time set off by a separator (+10:00 | Headline+), screen-reader field labels (+Section:+)
    # and type labels with their marker (+Article type: Video+). The label and marker sets are
    # small, closed and multilingual (en, de, fr, es), matching {LinkDestination::TextClassifier}.
    #
    # A clock run straight into the headline (+10:00 Budget vote+) is not noise by text alone:
    # the extractors drop teaser clock elements ({.clock_piece?}) before the text is joined, and
    # judge kicker child elements with {.noise_piece?}.
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
      # Leading noise pieces, repeated: stray separators, separated clocks, field labels, type label plus marker.
      NOISE_PREFIX = /
        \A(?:
          [[:space:]:|•·–—]+
          | #{CLOCK}(?:\s*Uhr)?(?=[[:space:]]*(?:[:|•·–—]|\z))
          | (?:section|category|rubrik|ressort|kategorie|rubrique|cat[ée]gorie|secci[óo]n|categor[íi]a)\s*:
          | (?:article\s+type|content\s+type|artikeltyp|beitragstyp|inhaltstyp|type\s+d['’]article
              |type\s+de\s+contenu|tipo\s+de\s+art[íi]culo|tipo\s+de\s+contenido)\s*:
            (?:\s*(?:#{Regexp.union(TYPE_MARKERS.sort_by { -_1.length }).source})(?![[:alnum:]]))?
        )+
      /ix
      # Trailing stray separators (a kicker that already ends in +:+ or + :+).
      STRAY_SUFFIX = /[[:space:]:|•·–—]+\z/
      # The inline kicker boundary of +Kicker : Headline+: a whitespace-preceded colon after at most
      # eight words ending in a letter or closing quote/bracket, so a score (+16 : 9+) keeps its colon.
      SPACED_COLON = /\A((?:[^[:space:]]+[[:space:]]+){0,7}?[^[:space:]]*[\p{L}"'“”’»›)\]])[[:space:]]+:[[:space:]]*/
      # A kicker that already ends a sentence (+Kicker?+) joins its headline with a space, not a colon.
      TERMINAL_PUNCTUATION = /[?!…‽]\z/
      private_constant :NOISE_PREFIX, :STRAY_SUFFIX, :SPACED_COLON, :TERMINAL_PUNCTUATION

      class << self
        ##
        # @param text [String, nil] title text as extracted
        # @return [String, nil] +text+ with whitespace runs (newlines included) collapsed and trimmed, or nil when blank
        def collapse(text)
          collapsed = text.to_s.gsub(/[[:space:]]+/, ' ').strip
          collapsed unless collapsed.empty?
        end

        ##
        # @param headline [String, nil] headline text as extracted
        # @param kicker [String, nil] kicker / eyebrow text, when the source exposes one
        # @return [String, nil] +Kicker: Headline+, the clean headline, or nil when it is blank
        def compose(headline, kicker: nil)
          head = clean(headline)
          return unless head

          top = clean(kicker)
          return head if top.nil? || noise_kicker?(top) || prefixed?(head, top)

          "#{top}#{top.match?(TERMINAL_PUNCTUATION) ? ' ' : SEPARATOR}#{head}"
        end

        ##
        # Whether a teaser element's text is only a clock time (+19:47+, +10:00 CET+). Extractors drop
        # such elements, and +time+ elements, from headline text before it is joined.
        #
        # @param text [String, nil] visible text of one element
        # @return [Boolean]
        def clock_piece?(text) = collapse(text).to_s.match?(CLOCK_PIECE)

        ##
        # Whether one child element of a kicker is noise on its own: blank, a clock time, a field
        # label (+Thema:+, +Section:+) or a type marker. Extractors drop such children from the kicker.
        #
        # @param text [String, nil] visible text of one kicker child element
        # @return [Boolean]
        def noise_piece?(text)
          piece = collapse(text)
          piece.nil? || piece.end_with?(':') || piece.match?(CLOCK_PIECE) || TYPE_MARKERS.include?(piece.downcase)
        end

        private

        def clean(text)
          return unless (collapsed = collapse(text))

          cleaned = collapsed.sub(NOISE_PREFIX, '').sub(STRAY_SUFFIX, '').sub(SPACED_COLON, "\\1#{SEPARATOR}")
          cleaned unless cleaned.empty?
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
