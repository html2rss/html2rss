# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Romanian. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +ro+, and nowhere else. Its
    # label words are ordinary words (+contact+, +meniu+, +conectare+, +caută+), so no term is read as a prefix or a
    # substring: each label is listed whole and read as a whole text only (no trailing word, no headline opener, see
    # {LinkDestination::TextClassifier}). Terms are written in NFC, the form the classifier normalizes to, so
    # decomposed input and upper case ("AUTENTIFICARE", "ABONEAZĂ-TE") match. Only the concepts read through a
    # {Scope} are listed (label words, the call to action, read-more, recommended and the new-window notice); the
    # others stay +NONE+ until their readers take the page scope. It lists no type marker (stripping a short kicker
    # could leave a headline below the title floor), no section name (+politică+, +sport+, +externe+ and +actualitate+
    # are topics a feed may carry), no pager label, no path word, and not the bare labels judged too likely to be a
    # headline (+publicitate+ is advertising, +abonare+ a subscription story, +înregistrare+ a recording, +detalii+
    # details, +redacția+ the editorial staff, +acasă+ "at home"). Some common words stay listed as whole labels by
    # judgment (+contact+, +meniu+, +caută+, +comentarii+): a one-word text equal to one reads as chrome, while a
    # longer headline that opens with one stays a headline. A bracketed count after an own label is chrome; a bare
    # count or a year after one is a headline. +contact+ also keeps the shared English, French and Dutch reading (one
    # trailing word plus a count), so "Contact direct 12" and "Contact 2026" are chrome. No "more" or "all" label is a
    # chrome term (+vezi toate+, +toate știrile+): a chrome link that is a card's only link empties the card, so
    # these and +mai multe+, +mai mult+, +vezi mai multe+ and +vezi mai mult+ are read-more labels instead. A term whose
    # precision is unclear is left out.
    #
    # Romanian writes +ș+ and +ț+ two ways, both common on real pages: comma-below (U+0219, U+021B) and the legacy
    # cedilla forms (U+015F, U+0163). Each label is written once with the comma-below letters and expanded below
    # into one fragment per concept, so every +ș+ also reads +ş+ and every +ț+ also reads +ţ+; the case-insensitive
    # match covers the capitals of both. A label typed without its other Romanian letters ("stiri", "conditii") is
    # not read.
    Ro = Language.new(
      code: :ro,
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
          'abonează-te la newsletter', 'abonează-te la notificări', 'abonează-te acum', 'abonează-te gratuit',
          'abonează-te', 'înscrie-te la newsletter', 'înscrie-te acum', 'înregistrează-te acum', 'devino membru',
          'lasă un comentariu', 'scrie un comentariu', 'adaugă un comentariu', 'distribuie articolul',
          'distribuie acest articol', 'distribuie știrea', 'distribuie această știre'
        ],
        read_more: [
          'citește mai mult', 'citește mai multe', 'citește mai departe', 'citește tot articolul', 'citește articolul',
          'citește articolul complet', 'citește continuarea', 'citește tot', 'află mai multe', 'află mai mult',
          'mai multe', 'mai mult', 'vezi mai multe', 'vezi mai mult', 'vezi detalii', 'continuă lectura',
          'citește în continuare', 'vezi toate', 'vezi toate articolele', 'vezi toate știrile', 'vezi mai multe știri',
          'toate articolele', 'toate știrile', 'citește mai multe știri'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'se deschide într-o fereastră nouă', 'se deschide în fereastră nouă', 'se deschide într-o filă nouă',
          'se deschide în filă nouă', 'se deschide într-un tab nou', 'se deschide în tab nou',
          'deschide într-o fereastră nouă', 'deschide în fereastră nouă', 'deschide într-o filă nouă',
          'deschide în filă nouă'
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
          'autentificare', 'autentifică-te', 'conectare', 'conectează-te', 'cont nou', 'creează cont',
          'creare cont', 'contul meu', 'deconectare', 'înregistrează-te', 'căutare', 'caută', 'despre noi',
          'contact', 'contactează-ne', 'contactați-ne', 'politica de confidențialitate',
          'politică de confidențialitate', 'politica de cookie', 'politica de cookies', 'politica de cookie-uri',
          'setări cookie', 'setări cookie-uri', 'gestionează cookie-urile', 'termeni și condiții',
          'termenii și condițiile', 'harta site-ului', 'harta site', 'întrebări frecvente', 'meniu', 'meniul',
          'pagina principală', 'comentarii', 'comentează', 'distribuie', 'partajează',
          'urmărește-ne', 'descarcă aplicația', 'sari la conținut', 'treci la conținut', 'salt la conținut',
          'sari la conținutul principal', 'treci la conținutul principal'
        ],
        recommended: [
          'articole similare', 'articole asemănătoare', 'articole recomandate', 'articole conexe',
          'știri similare', 'știri recomandate', 'știri conexe', 'subiecte conexe', 'citește și', 'vezi și',
          'te-ar putea interesa', 'ți-ar putea plăcea', 'poate te interesează', 'recomandări pentru tine',
          'recomandările noastre'
        ]
      }.transform_values do |labels|
        fold = ->(word) { word.gsub('ș', '(?:ș|ş)').gsub('ț', '(?:ț|ţ)') }
        labels.empty? ? labels : [Regexp.new(labels.map { _1.split.map(&fold).join('\s+') }.join('|'))]
      end.freeze
    )
  end
end
