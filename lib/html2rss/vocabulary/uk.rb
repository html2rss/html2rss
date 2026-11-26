# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Ukrainian. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +uk+, and nowhere else, so
    # +:all+, +ru+ and every other language read exactly what they read without it. Ukrainian is inflected and a
    # headline may open with a label noun ("Пошук зниклих триває", "Реєстрація виборців завершилась"), so no term is
    # read as a prefix: each label form is listed whole and read as a whole text only (no trailing word, no headline
    # opener, see {AutoSource::LinkDestination::TextClassifier}). A label with an apostrophe lists its three spellings
    # (+'+, +’+,
    # +ʼ+). Only the concepts read through a {Scope} are listed (label words, the call to action, read-more and the
    # new-window notice); the others stay +NONE+ until their readers take the page scope. It lists no type marker
    # (stripping a short kicker could leave a headline below the title floor), no section name and no bare
    # +реклама+ (the trade is also news). A term whose precision is unclear is left out.
    Uk = Language.new(
      code: :uk,
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
          'підписатися', 'підписуйтесь', 'підписатися на розсилку', 'підписатися на новини', 'поділитися',
          'поділіться', 'зареєструватися', 'залишити коментар', 'додати коментар', 'написати коментар',
          /зв[ʼ'’]яжіться\s+з\s+нами/, 'напишіть нам', 'увійти'
        ],
        read_more: [
          'читати далі', 'читати більше', 'читати повністю', 'читати продовження', 'читайте далі', 'докладніше',
          'детальніше', 'дізнатися більше', 'дізнайтеся більше', 'читати статтю повністю'
        ],
        list_more: NONE,
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/(?:відкриється|відкривається)\s+(?:у|в)\s+нов(?:ому\s+вікні|ій\s+вкладці)/],
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
          'про нас', 'про компанію', 'про проєкт', 'про проект', 'про сайт', 'про редакцію', 'контакти', 'вхід',
          'увійти', 'вийти', 'реєстрація', 'пошук', 'підписка', 'підписатися', 'поділитися', 'закрити', 'меню',
          'коментарі', 'карта сайту', 'політика конфіденційності', 'умови використання',
          'правила користування', 'угода користувача', 'публічна оферта', 'для рекламодавців'
        ],
        recommended: [
          'читайте також', 'вам може сподобатися', 'вас також може зацікавити', 'вас може зацікавити',
          'рекомендуємо прочитати', 'рекомендовані матеріали', 'рекомендовані статті', 'схожі матеріали',
          'схожі новини', /пов[ʼ'’]язані\s+(?:матеріали|статті|новини)/
        ]
      }.freeze
    )
  end
end
