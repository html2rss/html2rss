# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # English.
    En = Language.new(
      code: :en,
      terms: {
        path_section: %w[
          articles blog blogs changelogs insights launches news posts releases stories updates teasers cards
        ],
        path_article: %w[article changelog insight launch post release story update teaser card],
        path_profile: %w[author authors staff journalist journalists players],
        path_office: %w[contributor contributors],
        path_non_article: %w[
          games sudoku crossword crosswords quiz quizzes horoscope horoscopes obituary obituaries
          livestream livestreams player
        ],
        path_taxonomy: %w[category categories tag tags theme themes topic topics],
        path_vanity: %w[join membership plus premium pricing plans subscribe signup],
        path_soft_utility: %w[
          for-you join member members membership newsletter newsletters plans plus premium pricing recommended
        ],
        path_chrome: %w[
          about account archive archives author authors comment comments contact feedback help login logout
          notification notifications preference preferences profile register search settings share signup
          subscribe feed feeds comment-feed comments-feed privacy terms cookie cookies user users
        ],
        path_media: %w[video videos podcast podcasts audio audios],
        path_deep_post_context: %w[press newsroom],
        type_marker: [
          'news', 'news article', 'press release', 'video', 'audio', 'podcast', 'gallery', 'live', 'live blog',
          'full episode'
        ],
        utility_prefix: [
          'view all', 'see all', 'all news', 'subscribe', 'newsletter', 'comment feed', 'comments feed', 'join',
          'premium', 'plus'
        ],
        utility: [
          'about', 'contact', 'comment', 'comments', 'join', 'log in', 'login', 'member', 'membership', 'plus',
          'premium', 'pricing', 'see all', 'share', 'sign up', 'signup', 'subscribe', 'view all'
        ],
        recommended: ['recommended', 'recommended for you'],
        utility_cta: [
          'subscribe to', 'share this', 'log in to', 'login to', 'sign in to', 'sign up for', 'sign up to',
          'contact us', 'join our', 'leave a comment', 'leave a reply', 'follow us on'
        ],
        read_more: [
          'read more', 'read on', 'continue reading', 'keep reading', 'learn more', 'find out more',
          /read\s+(?:the\s+)?(?:full\s+|whole\s+)?(?:story|article)/, 'read the rest'
        ],
        topic_lead: ['more'],
        topic_preposition: %w[about on from],
        read_more_suffix: NONE,
        new_window_notice: [/opens\s+in\s+(?:a\s+)?new\s+(?:window|tab)/],
        paid_label: [
          /sponsored(?:\s+(?:content|post|story))?/, 'advertorial', /(?:paid|partner)\s+content/, 'paid post',
          /sponsored\s+by(?:\s+\S+){0,5}/
        ],
        ad_word: %w[ad advertisement promoted],
        field_label: %w[section category topic article],
        type_label: ['article type', 'content type'],
        pager_label: [/pagination(?!\p{L})/, /pager\b/, /paging\b/, /page\snavigation\b/],
        page_link: %w[prev previous next older newer first last],
        page_link_label: NONE,
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: %w[podcast episode audio],
        podcast_unspaced: NONE
      }.freeze,
      ambiguous: {
        utility_prefix: %w[plus],
        utility: %w[comment plus],
        path_chrome: %w[comment],
        path_taxonomy: %w[theme themes],
        path_vanity: %w[plus],
        path_soft_utility: %w[plus]
      }.freeze
    )
  end
end
