# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Arabic. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +ar+, and nowhere else. Arabic
    # attaches prefixes to words (+ال+, +و+, +ف+, +ب+, +ل+, +ك+), so no term is read as a prefix or a substring: each
    # label is listed whole, and an attached form only when it is a label of its own (+للمزيد+), read as a whole text
    # only (no trailing word, no headline opener, see {LinkDestination::TextClassifier}). Only the concepts read
    # through a {Scope} are listed (label words, the call to action, read-more and the new-window notice); the others
    # stay +NONE+ until their readers take the page scope. It lists no type marker (stripping a short kicker could
    # leave a headline below the title floor) and no section name. Arabic spelling only: Persian forms (+ی+, +ک+)
    # belong to {Fa}. A term whose precision is unclear is left out.
    Ar = Language.new(
      code: :ar,
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
          'اشترك الآن', 'اشترك معنا', 'اشترك في النشرة البريدية', 'اشترك في نشرتنا البريدية', 'شارك المقال',
          'شارك الخبر', 'أضف تعليقا', 'أضف تعليقاً', 'اترك تعليقا', 'اترك تعليقاً', 'سجل دخولك'
        ],
        read_more: [
          'اقرأ المزيد', 'قراءة المزيد', 'اقرأ أكثر', 'تابع القراءة', 'أكمل القراءة', 'اقرأ المقال كاملا',
          'اقرأ المقال كاملاً', 'اقرأ الخبر كاملا', 'اقرأ الخبر كاملاً', 'المزيد من التفاصيل', 'للمزيد',
          'للمزيد من التفاصيل'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/يفتح\s+في\s+(?:نافذة|علامة\s+تبويب|تبويب)\s+جديد[ةه]/],
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
          'تسجيل الدخول', 'تسجيل الخروج', 'إنشاء حساب', 'إنشاء حساب جديد', 'من نحن', 'اتصل بنا',
          'اتصلوا بنا', 'تواصل معنا', 'سياسة الخصوصية', 'الشروط والأحكام', 'الأحكام والشروط', 'شروط الاستخدام',
          'خريطة الموقع', 'شارك', 'اشترك', 'إغلاق', 'المزيد', 'عرض الكل', 'عرض المزيد'
        ],
        recommended: [
          'مقالات ذات صلة', 'أخبار ذات صلة', 'مواضيع ذات صلة', 'موضوعات ذات صلة', 'ذات صلة', 'اقرأ أيضا',
          'اقرأ أيضاً', 'قد يعجبك أيضا', 'قد يعجبك أيضاً', 'شاهد أيضا', 'شاهد أيضاً', 'مقالات مقترحة',
          'أخبار مقترحة'
        ]
      }.freeze
    )
  end
end
