# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Hebrew. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +he+ (the legacy tag +iw+ is not
    # mapped, so such a page reads the +all+ scope), and nowhere else. Hebrew attaches prefixes to nouns ("הרשמה
    # לבתי הספר", "כניסה לתוקף"), so no term is read as a prefix: each label form is listed whole and read as a whole
    # text only (no trailing word, no headline opener, see {LinkDestination::TextClassifier}). Only the concepts read
    # through a {Scope} are listed (label words, the call to action, read-more and the new-window notice); the others
    # stay +NONE+ until their readers take the page scope. It lists no type marker (stripping a short kicker could
    # leave a headline below the title floor) and no section name (+חדשות+, +ספורט+ and +תרבות+ are topics a feed may
    # carry). A term whose precision is unclear is left out.
    He = Language.new(
      code: :he,
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
        utility_prefix: NONE,
        utility_cta: [
          'הרשמה לניוזלטר', 'הירשמו לניוזלטר', 'הצטרפו לניוזלטר', 'רכשו מינוי', 'לרכישת מינוי', 'הירשמו',
          'התחברו', 'שתפו', 'הוסיפו תגובה', 'כתבו תגובה'
        ],
        read_more: [
          'קראו עוד', 'קרא עוד', 'קראי עוד', 'להמשך קריאה', 'המשך קריאה', 'להמשך הכתבה',
          'לכתבה המלאה', 'למידע נוסף', 'עוד פרטים'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/(?:נפתח|נפתחת|פתיחה)\s+ב(?:חלון|לשונית|כרטיסייה)\s+(?:חדש|חדשה)/],
        paid_label: NONE,
        ad_word: NONE,
        field_label: NONE,
        type_label: NONE,
        pager_label: NONE,
        page_link: NONE,
        page_link_label: NONE,
        clock_suffix: NONE,
        date_piece: NONE,
        element_label: NONE,
        podcast_word: NONE,
        podcast_unspaced: NONE,
        type_marker: NONE,
        utility: [
          'התחברות', 'תנאי שימוש', 'תנאי השימוש', 'מדיניות פרטיות', 'מדיניות הפרטיות',
          'הצהרת נגישות', 'צרו קשר', 'יצירת קשר', 'אודות', 'מפת האתר', 'פרסמו אצלנו', 'עמוד הבית',
          'התנתקות', 'לתוכן העיקרי', 'דלג לתוכן'
        ],
        recommended: [
          'קראו גם', 'כתבות קשורות', 'כתבות נוספות', 'כתבות מומלצות', 'עוד בנושא'
        ]
      }.freeze
    )
  end
end
