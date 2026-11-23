# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Adds the Arabic-keyboard spelling (+ي+, +ك+ for +ی+, +ک+) to each label, so a page typed either way reads alike.
    ARABIC_KEYBOARD_SPELLINGS = ->(terms) { terms.flat_map { [_1, _1.tr('یک', 'يك')] }.uniq.freeze }
    private_constant :ARABIC_KEYBOARD_SPELLINGS

    # Persian (Farsi). It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +fa+, and nowhere
    # else. Persian writes compounds with a zero-width non-joiner (+ثبت‌نام+, +دیدگاه‌ها+) or a space, and attaches
    # suffixes and particles to nouns, so no term is read as a prefix or a substring: each label is listed whole, in
    # its ZWNJ and spaced spellings, read as a whole text only (no trailing word, no headline opener, see
    # {LinkDestination::TextClassifier}). Pages typed on an Arabic keyboard write +ي+ and +ك+ for +ی+ and +ک+, so a
    # label with either letter is listed in both spellings (+ARABIC_KEYBOARD_SPELLINGS+); the page text is never
    # normalized. Only the concepts read through a {Scope} are listed (label words, the call to action, read-more
    # and the new-window notice); the others stay +NONE+ until their readers take the page scope. It lists no type
    # marker (stripping a short kicker could leave a headline below the title floor) and no section name
    # (+دیدگاه+ is the opinion section). A term whose precision is unclear is left out.
    Fa = Language.new(
      code: :fa,
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
        utility_cta: ARABIC_KEYBOARD_SPELLINGS.call(
          [
            'اشتراک در خبرنامه', 'مشترک شوید', 'همین حالا مشترک شوید', 'نظر خود را بنویسید', 'دیدگاه خود را بنویسید',
            'نظر بگذارید', 'دیدگاه بگذارید', 'وارد شوید', 'به اشتراک بگذارید', 'ثبت‌نام در خبرنامه',
            'ثبت نام در خبرنامه'
          ]
        ),
        read_more: ARABIC_KEYBOARD_SPELLINGS.call(
          [
            'ادامه مطلب', 'ادامه خبر', 'ادامه مطلب را بخوانید', 'بیشتر بخوانید', 'مطالعه بیشتر', 'متن کامل',
            'متن کامل خبر', 'مشاهده متن کامل', 'جزئیات بیشتر', 'جزییات بیشتر'
          ]
        ),
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/در\s+(?:پنجره|زبانه|تب)\s+جد[یي]د\s+باز\s+م[یي][‌\s]?شود/],
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
        utility: ARABIC_KEYBOARD_SPELLINGS.call(
          [
            'ورود', 'ورود به حساب', 'ورود به حساب کاربری', 'خروج', 'خروج از حساب', 'خروج از حساب کاربری', 'جستجو',
            'جست‌وجو', 'جست و جو', 'جستجو در سایت', 'درباره ما', 'تماس با ما', 'ارتباط با ما', 'حریم خصوصی',
            'سیاست حفظ حریم خصوصی', 'سیاست حریم خصوصی', 'شرایط استفاده', 'شرایط و ضوابط',
            'نقشه سایت', 'راهنما', 'خبرنامه', 'عضویت', 'عضویت در خبرنامه', 'اشتراک', 'اشتراک‌گذاری', 'اشتراک گذاری',
            'ثبت‌نام', 'ثبت نام', 'نظرات', 'ارسال نظر', 'ارسال دیدگاه', 'بستن', 'بیشتر', 'مشاهده بیشتر',
            'مشاهده همه', 'منو', 'صفحه اصلی'
          ]
        ) + [%r{ورود(?:\s+(?:و|[یي]ا)\s+|\s*[/|]\s*)ثبت(?:‌|\s)?نام}],
        recommended: ARABIC_KEYBOARD_SPELLINGS.call(
          [
            'مطالب مرتبط', 'اخبار مرتبط', 'خبرهای مرتبط', 'مطلب مرتبط', 'خبر مرتبط', 'مطالب مشابه', 'اخبار مشابه',
            'مطالب پیشنهادی', 'همچنین بخوانید'
          ]
        )
      }.freeze
    )
  end
end
