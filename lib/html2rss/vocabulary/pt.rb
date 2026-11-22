# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Portuguese: only the forms that exist today (a pagination noun) and the ambiguous words Spanish shares
    # (+sobre+, +tema+, +entrada+) and the international +plus+; the rest are not yet supported.
    Pt = Language.new(
      code: :pt,
      terms: {
        path_section: %w[entradas],
        path_article: %w[entrada],
        path_profile: NONE,
        path_office: NONE,
        path_non_article: NONE,
        path_taxonomy: %w[tema temas],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[sobre],
        path_media: NONE,
        path_deep_post_context: NONE,
        type_marker: NONE,
        utility_prefix: ['plus'],
        utility: %w[sobre plus],
        recommended: NONE,
        read_more: NONE,
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: NONE,
        paid_label: NONE,
        ad_word: NONE,
        field_label: NONE,
        type_label: NONE,
        pager_label: [/paginação(?!\p{L})/, /paginacao(?!\p{L})/],
        page_link: NONE,
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[sobre plus],
        path_section: %w[entradas],
        path_article: %w[entrada],
        path_taxonomy: %w[tema temas],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus],
        path_chrome: %w[sobre]
      }.freeze
    )
  end
end
