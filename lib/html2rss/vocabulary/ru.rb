# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Russian. A word with +ё+ is listed with its +е+ spelling too (a fragment, or both strings). Russian is
    # inflected, so a term is the explicit form a link label uses: the imperative or infinitive of a call to
    # action, the nominative of a noun. A noun that opens ordinary headlines (+комментарий+, +регистрация+,
    # +рассылка+, +Рекомендованное…+) is left out of the loosely read concepts; a headline is never a label.
    # Russian sites write their paths in Latin letters (+/news/+, +/tag/+), which the other languages already
    # read; a path word is listed only where Cyrillic segments occur in practice (+/видео/+, +/пресс-релизы/+,
    # +/помощь/+), and every other path concept is {NONE}.
    Ru = Language.new(
      code: :ru,
      terms: {
        path_section: NONE,
        path_article: NONE,
        path_profile: NONE,
        path_office: NONE,
        path_non_article: NONE,
        path_taxonomy: NONE,
        path_vanity: NONE,
        path_soft_utility: NONE,
        path_chrome: %w[
          о-нас о-проекте о-сайте о-редакции контакты контакт архив поиск помощь справка вход войти регистрация
          профиль конфиденциальность политика-конфиденциальности комментарии реклама
        ],
        path_media: %w[видео подкаст подкасты аудио],
        path_deep_post_context: %w[пресс-центр пресс-релизы],
        type_marker: [
          'видео', 'аудио', 'фото', 'галерея', 'фотогалерея', 'прямой эфир', 'трансляция', 'онлайн-трансляция',
          'пресс-релиз', 'подкаст', 'полный выпуск'
        ],
        utility_prefix: ['смотреть все', 'смотреть всё', 'показать все', 'подпишитесь', 'подписывайтесь'],
        utility: [
          'о нас', 'о компании', 'о проекте', 'о сайте', 'о редакции', 'контакты', 'обратная связь', 'войти',
          'зарегистрироваться', 'поделиться', 'подписаться', 'смотреть все', 'смотреть всё', 'показать все'
        ],
        recommended: ['вам может понравиться', 'рекомендуем почитать', 'рекомендуем прочитать'],
        utility_cta: [
          'подпишитесь на', 'подписывайтесь на', 'поделитесь', 'свяжитесь с нами', 'напишите нам',
          'зарегистрируйтесь', 'присоединяйтесь к', 'оставьте комментарий', /войдите[,\s]+(?:чтобы|или)/,
          # Infinitives stay a whole label: they are not call-to-action openers of a sentence.
          /(?:оставить|добавить|написать)\s+комментарий(?=[\s\p{P}\p{S}]*\z)/
        ],
        read_more: [
          'читать далее', 'читать дальше', 'читать полностью', 'читать продолжение', /читать\s+(?:ещё|еще)/,
          /читать\s+(?:всё|все)/, 'читайте далее', 'подробнее', 'подробности', 'узнать больше'
        ],
        topic_lead: NONE,
        topic_preposition: ['на тему'],
        read_more_suffix: NONE,
        new_window_notice: [/(?:открывается|откроется)\s+в\s+нов(?:ом\s+окне|ой\s+вкладке)/],
        paid_label: [
          'на правах рекламы', /партн(?:ё|е)рский\s+(?:материал|контент)/, /партн(?:ё|е)рские\s+материалы/,
          /материал\s+партн(?:ё|е)ра/, 'спонсорский материал', 'рекламный материал'
        ],
        ad_word: %w[реклама],
        field_label: %w[раздел рубрика категория тема статья],
        type_label: ['тип статьи', 'тип материала', 'тип контента'],
        pager_label: [/пагинация(?!\p{L})/, 'навигация по страницам', 'постраничная навигация'],
        page_link: NONE,
        page_link_label: [
          /(?:предыдущ|следующ)(?:ая|ий)(?:\s+(?:страница|статья|новость|запись))?/, 'далее', 'назад', /впер(?:ё|е)д/,
          'старые записи', 'новые записи', 'более ранние', 'более поздние'
        ],
        clock_suffix: %w[мск],
        date_piece: NONE,
        element_label: NONE,
        podcast_word: %w[подкаст подкасты подкастов],
        podcast_unspaced: NONE
      }.freeze
    )
  end
end
