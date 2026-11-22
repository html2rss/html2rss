# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Dutch.
    Nl = Language.new(
      code: :nl,
      terms: {
        path_section: %w[nieuws nieuwsberichten artikelen berichten],
        path_article: %w[bericht],
        path_profile: %w[journalisten],
        path_office: %w[redactie],
        path_non_article: %w[spellen quizzen horoscoop overlijdensberichten],
        path_taxonomy: %w[thema],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[
          over-ons contact archief zoeken hulp inloggen aanmelden registreren account profiel privacy voorwaarden
          reacties
        ],
        path_media: %w[video videos podcast podcasts audio],
        path_deep_post_context: %w[persberichten pers],
        type_marker: ['liveblog', 'fotogalerij', 'persbericht', 'volledige aflevering'],
        utility_prefix: [
          'bekijk alles', 'alles bekijken', 'al het nieuws', 'abonneren', 'nieuwsbrief', 'lid worden', 'plus'
        ],
        utility: [
          'over ons', 'contact', 'reacties', 'inloggen', 'aanmelden', 'delen', 'abonneren', 'registreren',
          'bekijk alles', 'nieuwsbrief', 'lid worden', 'lidmaatschap', 'plus'
        ],
        recommended: ['aanbevolen', 'aanbevolen voor jou'],
        read_more: [
          'lees meer', 'lees verder', 'verder lezen', 'meer lezen', 'meer informatie', 'meer weten',
          /lees\s+(?:het\s+)?(?:hele|volledige)\s+artikel/
        ],
        topic_lead: ['meer'],
        topic_preposition: %w[over van],
        read_more_suffix: NONE,
        new_window_notice: [/opent\s+in\s+(?:een\s+)?nieuw(?:e)?\s+(?:venster|tabblad)/],
        paid_label: [/gesponsord(?:e\s+(?:inhoud|content))?(?:\s+door(?:\s+\S+){0,5})?/],
        ad_word: %w[advertentie reclame],
        field_label: %w[sectie categorie onderwerp rubriek],
        type_label: ['artikeltype', 'inhoudstype', 'soort artikel'],
        pager_label: [/paginatie(?!\p{L})/],
        page_link: NONE,
        page_link_label: [
          /(?:vorige|volgende)(?:\s+pagina)?/, /(?:oudere|nieuwere)(?:\s+(?:berichten|artikelen))?/, 'ouder',
          'nieuwer'
        ],
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[delen plus],
        path_taxonomy: %w[thema],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
