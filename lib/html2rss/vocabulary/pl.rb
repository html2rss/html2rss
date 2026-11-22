# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Polish.
    Pl = Language.new(
      code: :pl,
      terms: {
        path_section: %w[aktualnosci aktualności wiadomosci wiadomości artykuly artykuły wpisy],
        path_article: %w[artykul artykuł wpis],
        path_profile: %w[autorzy dziennikarz dziennikarze],
        path_office: %w[redakcja],
        path_non_article: %w[gry kviz horoskopy nekrolog nekrologi nazywo],
        path_taxonomy: NONE,
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: NONE,
        path_media: NONE,
        path_deep_post_context: NONE,
        type_marker: ['wideo', 'galeria', 'na żywo', 'relacja na żywo', 'komunikat prasowy', 'cały odcinek'],
        utility_prefix: [
          'zobacz wszystko', 'wszystkie wiadomości', 'wszystkie wiadomosci', 'subskrybuj', 'newsletter',
          'dołącz', 'dolacz', 'plus'
        ],
        utility: [
          'o nas', 'kontakt', 'komentarze', 'zaloguj się', 'zaloguj sie', 'zarejestruj się', 'zarejestruj sie',
          'udostępnij', 'udostepnij', 'subskrybuj', 'zobacz wszystko', 'dołącz', 'dolacz', 'plus'
        ],
        recommended: ['polecane', 'polecane dla ciebie'],
        read_more: [
          /czytaj\s+wi(?:ę|e)cej/, 'czytaj dalej', /dowiedz\s+si(?:ę|e)\s+wi(?:ę|e)cej/,
          /wi(?:ę|e)cej\s+informacji/, /czytaj\s+ca(?:ł|l)o(?:ś|s)(?:ć|c)/, /zobacz\s+wi(?:ę|e)cej/
        ],
        topic_lead: [/wi(?:ę|e)cej/],
        topic_preposition: ['o', 'na temat'],
        read_more_suffix: NONE,
        new_window_notice: [/otwiera\s+si(?:ę|e)\s+w\s+nowym\s+(?:oknie|karcie)/],
        paid_label: [
          'sponsorowane', /materia(?:ł|l)\s+(?:sponsorowany|partnera|partnerski|promocyjny|reklamowy)/,
          /materia(?:ł|l)y\s+(?:sponsorowane|partnera|partnerskie|promocyjne|reklamowe)/,
          /artyku(?:ł|l)\s+sponsorowany/
        ],
        ad_word: %w[reklama],
        field_label: ['sekcja', 'kategoria', 'temat', /dzia(?:ł|l)/, /artyku(?:ł|l)/],
        type_label: [/typ\s+artyku(?:ł|l)u/, /typ\s+tre(?:ś|s)ci/, /rodzaj\s+tre(?:ś|s)ci/],
        pager_label: [/paginacja(?!\p{L})/],
        page_link: NONE,
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[plus],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
