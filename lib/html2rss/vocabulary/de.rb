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
        path_media: NONE,
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
        clock_suffix: %w[Uhr],
        date_piece: NONE,
        element_label: NONE
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
