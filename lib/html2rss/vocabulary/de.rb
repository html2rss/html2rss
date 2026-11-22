# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # German.
    De = Language.new(
      code: :de,
      terms: {
        path_section: %w[nachrichten neuigkeiten aktuelles beitraege],
        path_article: %w[artikel beitrag],
        path_profile: %w[autor autoren redakteure],
        path_office: %w[redaktion],
        path_non_article: %w[
          spiele kreuzwortraetsel kreuzworträtsel quizze horoskop horoskope nachruf nachrufe traueranzeigen
          todesanzeigen
        ],
        path_taxonomy: %w[kategorie kategorien schlagwort schlagworte thema themen],
        path_vanity: %w[abonnieren abo plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[
          autor autoren archiv ueber-uns ueber ueberuns profil kontakt impressum suche hilfe anmelden registrieren
          konto registrierung anmeldung abonnieren abo datenschutz nutzungsbedingungen agb
        ],
        path_media: %w[video videos podcast podcasts audio],
        path_deep_post_context: %w[presse pressemitteilungen],
        type_marker: ['bildergalerie', 'fotostrecke', 'liveticker', 'pressemitteilung', 'ganze folge'],
        utility_prefix: [
          'alle anzeigen', 'alle news', 'abonnieren', 'newsletter', 'kommentar feed', 'mitmachen', 'plus'
        ],
        utility: [
          'ueber', 'über', 'ueber uns', 'über uns', 'kontakt', 'kommentar', 'kommentare', 'mitmachen', 'anmelden',
          'login', 'mitglied', 'mitgliedschaft', 'alle anzeigen', 'teilen', 'registrieren', 'abonnieren',
          'newsletter', 'plus'
        ],
        recommended: ['empfohlen', 'empfohlen fuer dich', 'empfohlen für dich'],
        utility_cta: [
          'abonnieren sie', 'werden sie mitglied', 'melden sie sich', 'kontaktieren sie uns', 'folgen sie uns',
          # Infinitive and noun forms open headlines ("Kommentare zum Artikel 13: ..."): a whole label only.
          /mitglied\s+werden(?=[\s\p{P}\p{S}]*\z|\s+und\b)/,
          /jetzt\s+(?:anmelden|registrieren)(?=[\s\p{P}\p{S}]*\z)/,
          /(?:diesen\s+)?artikel\s+teilen(?=[\s\p{P}\p{S}]*\z)/,
          /kommentare\s+(?:zum|zu\s+diesem)\s+artikel(?=[\s\p{P}\p{S}]*\z)/,
          /kommentar\s+schreiben(?=[\s\p{P}\p{S}]*\z)/
        ],
        read_more: [
          'weiterlesen', 'weiter lesen', 'mehr lesen', 'mehr erfahren', 'mehr dazu', 'mehr zum thema',
          'lesen sie mehr', 'lesen sie weiter', /(?:den\s+)?(?:ganzen|gesamten|vollst(?:ä|a)ndigen)\s+artikel\s+lesen/
        ],
        topic_lead: ['mehr'],
        topic_preposition: ['zu', 'zum thema', 'zum', 'zur', /(?:ü|ue)ber/, 'von'],
        read_more_suffix: NONE,
        new_window_notice: [/(?:ö|oe)ffnet\s+(?:sich\s+)?in\s+(?:einem\s+neuen|neuem)\s+(?:fenster|tab)/],
        paid_label: [/gesponsert(?:\s+von(?:\s+\S+){0,5})?/],
        ad_word: %w[anzeige werbung],
        field_label: %w[rubrik ressort kategorie thema artikel],
        type_label: %w[artikeltyp beitragstyp inhaltstyp],
        pager_label: [/paginierung\b/],
        page_link: NONE,
        page_link_label: [
          'vorherige', 'vorherige seite', 'nächste', 'nächste seite', 'naechste', 'naechste seite', 'ältere',
          'neuere', 'ältere beiträge', 'neuere beiträge', 'zurück', 'weiter'
        ],
        clock_suffix: %w[Uhr],
        date_piece: NONE,
        element_label: NONE,
        podcast_word: NONE,
        podcast_unspaced: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[ueber über teilen plus],
        path_chrome: %w[ueber],
        path_taxonomy: %w[thema themen],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
