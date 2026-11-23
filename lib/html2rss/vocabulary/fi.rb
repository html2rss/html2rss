# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Finnish. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +fi+, and nowhere else, so
    # +:all+ and every other language read exactly what they read without it. Finnish is written in Latin script and
    # is heavily inflected (case endings, no articles), so it lists each label form a site really writes whole
    # (+tietosuojaseloste+, +tietosuojalauseke+; +avautuu uuteen ikkunaan+, +aukeaa uuteen ikkunaan+) and never a
    # stem, a prefix or a substring: each label is read as a whole text only (no trailing word, no headline opener,
    # see {LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed (label words, the
    # call to action, read-more, recommended and the new-window notice); the others stay +NONE+ until their readers
    # take the page scope. It lists no type marker (stripping a short kicker could leave a headline below the title
    # floor), no section name (+kotimaa+, +ulkomaat+, +urheilu+, +talous+ and +kulttuuri+ are topics a feed may
    # carry), no pager label, no path word, and not the bare labels judged too likely to be a headline (+tilaa+,
    # +jaa+, +kommentoi+, +etsi+, +kuuntele+ and +pelaa+ are imperatives that open headlines, +luetuimmat+ and
    # +uusimmat+ are sections, +katso kaikki+, +näytä kaikki+, +näytä lisää+ and +lisää uutisia+ are list-level
    # "more" labels, listed under +list_more+ because as chrome they would empty a card whose only link carries
    # one). Some common words stay listed as whole labels by judgment (+hae+, +haku+, +valikko+, +kommentit+): a
    # one-word text equal to one reads as chrome, while a longer headline that opens with one stays a headline, and
    # a label followed by a year or a bare number stays a headline. A term whose precision is unclear is left out.
    Fi = Language.new(
      code: :fi,
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
          'tilaa uutiskirje', 'tilaa uutiskirjeemme', 'tilaa uutiskirjeet', 'tilaa lehti', 'tilaa nyt',
          'ryhdy tilaajaksi', 'liity jäseneksi', 'luo tunnus ilmaiseksi', 'kirjoita kommentti', 'jaa artikkeli',
          'jaa juttu', 'jaa tämä artikkeli', 'jaa tämä juttu', 'lähetä uutisvinkki', 'anna uutisvinkki'
        ],
        read_more: [
          'lue lisää', 'lue lisää tästä', 'lue lisää täältä', 'lue koko juttu', 'lue koko juttu tästä',
          'lue koko artikkeli', 'lue koko uutinen', 'lue koko kirjoitus', 'lue loppuun', 'lue juttu',
          'lue artikkeli', 'lue uutinen', 'jatka lukemista'
        ],
        list_more: [
          'näytä kaikki', 'katso kaikki', 'näytä lisää', 'katso lisää', 'lisää uutisia', 'lisää juttuja',
          'lisää artikkeleita', 'kaikki uutiset', 'kaikki artikkelit', 'kaikki jutut', 'näytä kaikki uutiset',
          'näytä kaikki jutut', 'näytä kaikki artikkelit', 'katso kaikki uutiset', 'katso kaikki jutut',
          'näytä lisää uutisia', 'näytä lisää juttuja', 'lataa lisää', 'lue lisää aiheesta',
          'aiheesta lisää'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'avautuu uuteen ikkunaan', 'avautuu uuteen välilehteen', 'avautuu uudessa ikkunassa',
          'avautuu uudessa välilehdessä', 'aukeaa uuteen ikkunaan', 'aukeaa uuteen välilehteen',
          'aukeaa uudessa ikkunassa', 'aukeaa uudessa välilehdessä', 'avaa uudessa ikkunassa',
          'avaa uudessa välilehdessä'
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
          'kirjaudu sisään', 'kirjaudu ulos', 'kirjaudu', 'rekisteröidy', 'luo tunnus', 'hae', 'haku',
          'ota yhteyttä', 'yhteystiedot', 'asiakaspalvelu', 'tietoa meistä', 'tietosuoja', 'tietosuojaseloste',
          'tietosuojalauseke', 'tietosuojakuvaus', 'tietosuojakäytäntö', 'evästekäytäntö', 'evästekäytännöt',
          'evästeasetukset', 'evästeet', 'käyttöehdot', 'käyttö- ja sopimusehdot', 'sopimusehdot', 'tilausehdot',
          'usein kysytyt kysymykset', 'ukk', 'valikko', 'avaa valikko', 'sulje valikko', 'etusivu', 'kommentit',
          'seuraa meitä', 'siirry sisältöön', 'siirry pääsisältöön', 'hyppää sisältöön', 'siirry sivuston hakuun',
          'saavutettavuusseloste', 'anna palautetta', 'takaisin sivun alkuun'
        ],
        recommended: [
          'lue myös', 'katso myös', 'samasta aiheesta',
          'aiheeseen liittyvää', 'aiheeseen liittyvät jutut', 'aiheeseen liittyvät artikkelit',
          'liittyvät artikkelit', 'liittyvät jutut', 'suositellut jutut', 'suositellut artikkelit',
          'sinulle suositeltua', 'muut lukivat myös'
        ]
      }.freeze
    )
  end
end
