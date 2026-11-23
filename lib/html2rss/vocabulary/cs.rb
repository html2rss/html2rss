# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Czech. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +cs+, and nowhere else. Czech
    # inflects nouns and verbs ("přihlásit se", "přihlaste se", "ochrana osobních údajů"), so no term is read as a
    # prefix or a substring: each label form is listed whole, read as a whole text only (no trailing word, no
    # headline opener, see {LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed
    # (label words, the call to action, read-more, recommended and the new-window notice); the others stay +NONE+
    # until their readers take the page scope. It lists no type marker (stripping a short kicker could leave a
    # headline below the title floor), no section name (+sport+, +ekonomika+ and +kultura+ are topics a feed may
    # carry), no pager label, no path word, and no label that is also a plausible short headline (+komentář+ and
    # +komentáře+ are an opinion section, +redakce+ an editorial office in a headline, +registrace+ and
    # +přihlášení+ are events, +předplatné+ a subscription story, +inzerce+ and +reklama+ the trade, +zavřít+ a
    # verb, +více+ and +vše+ bare words). A term whose precision is unclear is left out. Terms are NFC, the form
    # the classifier normalizes to, and the case-insensitive match reads +PŘIHLÁSIT SE+.
    Cs = Language.new(
      code: :cs,
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
          'přihlásit se k odběru', 'přihlaste se k odběru', 'přihlásit se k odběru newsletteru',
          'přihlaste se k odběru newsletteru', 'přihlásit se k rozesílce', 'odebírat newsletter', 'odebírat novinky',
          'koupit předplatné', 'objednat předplatné', 'zaregistrovat se', 'vytvořit účet', 'přidat komentář',
          'napsat komentář', 'okomentovat', 'sdílet článek', 'sdílet na facebooku', 'kontaktujte nás', 'napište nám',
          'podat inzerát'
        ],
        read_more: [
          'číst dále', 'číst více', 'číst dál', 'čtěte více', 'čtěte dále', 'celý článek', 'zobrazit celý článek',
          'přečíst celý článek', 'pokračovat ve čtení', 'přečtěte si více', 'zjistit více', 'více informací',
          'další informace', 'dočíst se více', 'zobrazit všechny', 'zobrazit vše', 'zobrazit více', 'zobrazit další',
          'načíst další', 'načíst více', 'všechny články', 'všechny zprávy', 'další články', 'další zprávy'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'otevře se v novém okně', 'otevře se v nové kartě', 'otevře se v novém panelu',
          'otevírá se v novém okně', 'otevírá se v nové kartě', 'otevřít v novém okně', 'otevřít v nové kartě',
          'odkaz se otevře v novém okně', 'odkaz se otevře v nové kartě'
        ],
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
          'přihlásit se', 'přihlásit', 'přihlaste se', 'odhlásit se', 'odhlásit', 'registrovat se', 'registrovat',
          'hledat', 'vyhledávání', 'o nás', 'kontakt', 'kontakty', 'ochrana soukromí', 'ochrana osobních údajů',
          'zpracování osobních údajů', 'zásady ochrany soukromí', 'zásady ochrany osobních údajů',
          'zásady zpracování osobních údajů', 'informace o zpracování osobních údajů', 'nastavení soukromí',
          'nastavení cookies', 'nastavení cookie', 'nastavení souborů cookie', 'zásady cookies', 'podmínky používání',
          'podmínky užívání', 'obchodní podmínky', 'všeobecné obchodní podmínky', 'všeobecné podmínky',
          'všeobecné smluvní podmínky', 'mapa stránek', 'nápověda', 'často kladené otázky', 'časté dotazy',
          'nejčastější dotazy', 'menu', 'úvodní stránka', 'hlavní stránka', 'domovská stránka', 'sdílet',
          'přeskočit na obsah', 'přeskočit na hlavní obsah', 'přejít na obsah', 'přejít k obsahu', 'můj účet',
          'moje předplatné', 'spravovat účet'
        ],
        recommended: [
          'související články', 'související zprávy', 'související témata', 'související obsah',
          'doporučené články', 'doporučujeme', 'doporučujeme přečíst', 'podobné články', 'podobné zprávy',
          'mohlo by vás zajímat', 'může vás zajímat', 'čtěte také', 'přečtěte si také'
        ]
      }.freeze
    )
  end
end
