# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Portuguese: only the forms that exist today (a pagination noun); the rest are not yet supported.
    Pt = Language.new(
      code: :pt,
      terms: {
        path_section: NONE,
        path_article: NONE,
        path_profile: NONE,
        path_office: NONE,
        path_non_article: NONE,
        path_taxonomy: NONE,
        path_vanity: NONE,
        path_soft_utility: NONE,
        path_chrome: NONE,
        path_media: NONE,
        path_deep_post_context: NONE,
        type_marker: NONE,
        utility_prefix: NONE,
        utility: NONE,
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
      }.freeze
    )
  end
end
