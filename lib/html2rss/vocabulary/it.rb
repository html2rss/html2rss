# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Italian.
    It = Language.new(
      code: :it,
      terms: {
        path_section: %w[notizie articoli novita novità aggiornamenti],
        path_article: %w[notizia articolo],
        path_profile: %w[autore autori giornalista giornalisti],
        path_office: %w[redazione],
        path_non_article: %w[giochi oroscopo oroscopi necrologio necrologi indiretta],
        path_taxonomy: %w[tema],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[chi-siamo contatti archivio cerca aiuto accedi registrati iscriviti abbonati profilo],
        path_media: %w[video podcast audio],
        path_deep_post_context: %w[comunicati-stampa sala-stampa ufficio-stampa],
        type_marker: [
          'diretta', 'in diretta', 'diretta streaming', 'fotogallery', 'galleria', 'comunicato stampa',
          'puntata completa'
        ],
        utility_prefix: ['vedi tutto', 'vedi tutti', 'tutte le notizie', 'abbonati', 'newsletter', 'iscriviti', 'plus'],
        utility: [
          'chi siamo', 'contatti', 'commenti', 'accedi', 'iscriviti', 'condividi', 'abbonati', 'registrati',
          'vedi tutto', 'abbonamento', 'plus'
        ],
        recommended: ['consigliato', 'consigliato per te'],
        utility_cta: [
          /iscriviti\s+(?:a|alla|al)/, /abbonati\s+(?:a|alla|al)/, 'condividi questo articolo',
          /condividi\s+l['’]articolo/, 'accedi per', 'registrati per', 'contattaci',
          /unisciti\s+(?:a|alla|al)/, 'lascia un commento'
        ],
        read_more: [
          'leggi tutto', /leggi\s+di\s+pi(?:ù|u)/, /leggi\s+l['’]articolo/, 'continua a leggere',
          /scopri\s+di\s+pi(?:ù|u)/, 'maggiori informazioni', 'ulteriori informazioni',
          /per\s+saperne\s+di\s+pi(?:ù|u)/, 'approfondisci'
        ],
        topic_lead: ['altro', /di\s+pi(?:ù|u)/],
        topic_preposition: %w[su riguardo],
        read_more_suffix: NONE,
        new_window_notice: [/si\s+apre\s+in\s+(?:una\s+)?nuova\s+(?:finestra|scheda)/],
        paid_label: [
          /(?:contenuto\s+)?sponsorizzat[oa](?:\s+(?:da|a\s+cura\s+di)(?:\s+\S+){0,5})?/,
          'informazione pubblicitaria', 'pubbliredazionale'
        ],
        ad_word: [/pubblicit(?:à|a)/],
        field_label: %w[sezione categoria argomento rubrica articolo],
        type_label: ['tipo di articolo', 'tipo di contenuto'],
        pager_label: [/paginazione(?!\p{L})/],
        page_link: NONE,
        page_link_label: [
          /(?:pagina\s+)?(?:precedente|successiv[oa]|prossim[oa])/, /pi(?:ù|u)\s+(?:vecchi|recenti)/, 'avanti',
          'indietro'
        ],
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: %w[episodio],
        podcast_unspaced: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[plus],
        path_taxonomy: %w[tema],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
