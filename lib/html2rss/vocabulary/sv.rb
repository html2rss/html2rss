# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Swedish.
    Sv = Language.new(
      code: :sv,
      terms: {
        path_section: %w[nyheter artiklar],
        path_article: %w[nyhet inlagg inlägg],
        path_profile: %w[skribent skribenter forfattare författare],
        path_office: %w[redaktion redaktionen],
        path_non_article: %w[spel dodsannonser dödsannonser],
        path_taxonomy: %w[tema],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[
          om-oss kontakt arkiv sok sök hjalp hjälp logga-in registrera profil integritet anvandarvillkor
          användarvillkor prenumerera nyhetsbrev kommentarer
        ],
        path_media: %w[video videor podcast podcasts audio],
        path_deep_post_context: %w[press pressrum pressmeddelanden],
        type_marker: [
          'bildspel', 'direkt', 'direktsändning', 'liverapport', 'livesändning', 'pressmeddelande', 'hela avsnittet'
        ],
        utility_prefix: ['visa alla', 'se alla', 'alla nyheter', 'prenumerera', 'nyhetsbrev', 'bli medlem', 'plus'],
        utility: [
          'om oss', 'kontakt', 'kommentarer', 'logga in', 'bli medlem', 'dela', 'prenumerera', 'registrera dig',
          'visa alla', 'se alla', 'nyhetsbrev', 'medlemskap', 'plus'
        ],
        recommended: ['rekommenderat', 'rekommenderat för dig', 'rekommenderat for dig'],
        utility_cta: [
          /prenumerera\s+p(?:å|a)/, 'dela den här artikeln', 'dela denna artikel', /logga\s+in\s+f(?:ö|o)r\s+att/,
          'registrera dig för', 'kontakta oss',
          /g(?:å|a)\s+med\s+i\s+(?:v(?:å|a)r(?:t|a)?|oss)\b/, 'skriv en kommentar', 'lämna en kommentar'
        ],
        read_more: [
          /l(?:ä|a)s\s+mer/, /l(?:ä|a)s\s+vidare/, /forts(?:ä|a)tt\s+l(?:ä|a)sa/, 'mer information',
          /l(?:ä|a)s\s+hela\s+artikeln/
        ],
        list_more: NONE,
        topic_lead: ['mer'],
        topic_preposition: %w[om av],
        read_more_suffix: NONE,
        new_window_notice: [/(?:ö|o)ppnas\s+i\s+(?:ett\s+)?nytt\s+(?:f(?:ö|o)nster|flik)/],
        paid_label: ['sponsrad', /sponsrat(?:\s+inneh(?:å|a)ll)?/, 'annonssamarbete'],
        ad_word: %w[annons reklam],
        field_label: ['sektion', 'kategori', /(?:ä|a)mne/],
        type_label: %w[innehållstyp],
        pager_label: [/paginering\b/],
        page_link: NONE,
        page_link_label: [
          /f(?:ö|o)reg(?:å|a)ende(?:\s+sida)?/, /n(?:ä|a)sta(?:\s+sida)?/, /(?:ä|a)ldre(?:\s+inl(?:ä|a)gg)?/,
          /nyare(?:\s+inl(?:ä|a)gg)?/
        ],
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: NONE,
        podcast_unspaced: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[dela plus],
        path_taxonomy: %w[tema],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
