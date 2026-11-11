# frozen_string_literal: true

module Html2rss
  class Article
    ##
    # Owns article title composition and the one title-noise vocabulary.
    #
    # Every title takes the form +Kicker: Headline+ (or just +Headline+). Both parts are
    # whitespace-collapsed, trimmed of stray separators, and stripped of leading noise: clock
    # times, screen-reader field labels (+Section:+) and type labels with their marker
    # (+Article type: Video+). The label and marker sets are small, closed and multilingual
    # (en, de, fr, es), matching {LinkDestination::TextClassifier}.
    module Title
      # Joins a kicker to its headline.
      SEPARATOR = ': '
      # Clock time of day (24h, or 12h with AM/PM). Description chip peeling reuses it. Case-sensitive:
      # a spaced lowercase +am+ is the German preposition (+9:15 am Bahnhof+), so only +9:15am+ takes it.
      CLOCK = /\d{1,2}:\d{2}(?::\d{2})?(?:\s*(?:AM|PM)|am|pm)?/
      # Content-type markers (lowercase). Description drops them as whole leftover lines.
      TYPE_MARKERS = Set[
        'news', 'news article', 'press release', 'video', 'audio', 'podcast', 'gallery', 'live', 'live blog',
        'bildergalerie', 'fotostrecke', 'liveticker', 'pressemitteilung',
        'vidéo', 'diaporama', 'en direct', 'communiqué de presse',
        'vídeo', 'galería', 'en directo', 'nota de prensa'
      ].freeze
      # Leading noise pieces, repeated: stray separators, clocks, field labels, type label plus marker.
      NOISE_PREFIX = /
        \A(?:
          [[:space:]:|•·–—]+
          | #{CLOCK}(?:\s*Uhr)?(?![[:alnum:]])
          | (?:section|category|rubrik|ressort|kategorie|rubrique|cat[ée]gorie|secci[óo]n|categor[íi]a)\s*:
          | (?:article\s+type|content\s+type|artikeltyp|beitragstyp|inhaltstyp|type\s+d['’]article
              |type\s+de\s+contenu|tipo\s+de\s+art[íi]culo|tipo\s+de\s+contenido)\s*:
            (?:\s*(?:#{Regexp.union(TYPE_MARKERS.sort_by { -_1.length }).source})(?![[:alnum:]]))?
        )+
      /ix
      # Trailing stray separators (a kicker that already ends in +:+ or + :+).
      STRAY_SUFFIX = /[[:space:]:|•·–—]+\z/
      private_constant :NOISE_PREFIX, :STRAY_SUFFIX

      class << self
        ##
        # @param headline [String, nil] headline text as extracted
        # @param kicker [String, nil] kicker / eyebrow text, when the source exposes one
        # @return [String, nil] +Kicker: Headline+, the clean headline, or nil when it is blank
        def compose(headline, kicker: nil)
          head = clean(headline)
          return unless head

          top = clean(kicker)
          top.nil? || noise_kicker?(top) || prefixed?(head, top) ? head : "#{top}#{SEPARATOR}#{head}"
        end

        private

        def clean(text)
          cleaned = text.to_s.gsub(/[[:space:]]+/, ' ').sub(NOISE_PREFIX, '').sub(STRAY_SUFFIX, '')
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
