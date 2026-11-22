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
        path_office: NONE,
        path_non_article: %w[spel dodsannonser dödsannonser],
        path_taxonomy: NONE,
        path_vanity: NONE,
        path_soft_utility: NONE,
        path_chrome: NONE,
        path_media: NONE,
        path_deep_post_context: NONE,
        type_marker: [
          'bildspel', 'direkt', 'direktsändning', 'liverapport', 'livesändning', 'pressmeddelande', 'hela avsnittet'
        ],
        utility_prefix: ['visa alla', 'se alla', 'alla nyheter', 'prenumerera', 'nyhetsbrev', 'bli medlem'],
        utility: [
          'om oss', 'kontakt', 'kommentarer', 'logga in', 'bli medlem', 'dela', 'prenumerera', 'registrera dig',
          'visa alla', 'se alla', 'nyhetsbrev', 'medlemskap'
        ],
        recommended: ['rekommenderat', 'rekommenderat för dig', 'rekommenderat for dig'],
        read_more: [
          /l(?:ä|a)s\s+mer/, /l(?:ä|a)s\s+vidare/, /forts(?:ä|a)tt\s+l(?:ä|a)sa/, 'mer information',
          /l(?:ä|a)s\s+hela\s+artikeln/
        ],
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
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE
      }.freeze
    )
  end
end
