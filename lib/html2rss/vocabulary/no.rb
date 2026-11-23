# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Norwegian, Bokmål and common Nynorsk forms. It is {PAGE_ONLY}: its terms apply on a page whose language resolves
    # to +no+ (the tags +no+, +nb+ and +nn+, with any region), and nowhere else, so +:all+ and every other language
    # read exactly what they read without it. Norwegian is written in Latin script and its label words are ordinary
    # words (+søk+ is "search", +kontakt+ "contact", +les+ "read"), so no term is read as a prefix or a substring:
    # each label is listed whole and read as a whole text only (no trailing word, no headline opener, see
    # {LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed (label words, the call
    # to action, read-more, recommended and the new-window notice); the others stay +NONE+ until their readers take
    # the page scope. It lists no type marker (stripping a short kicker could leave a headline below the title
    # floor), no section name (+nyheter+, +sport+, +kultur+, +meninger+ and +økonomi+ are topics a feed may carry),
    # no pager label, no path word, and not the bare labels judged too likely to be a headline (+del+ is a part of
    # a series, +hjelp+ is aid, +annonsering+ advertising, +presse+ the press, +siste nytt+ is a section,
    # +se alle spill+ and +flere spill+ are hubs). The list-level labels +se alle+, +vis alle+, +se flere+,
    # +flere nyheter+ and +alle saker+ are listed under +list_more+, because as chrome they would empty a card whose
    # only link carries one. Some common words stay listed as whole labels by judgment (+søk+, +meny+,
    # +personvern+): a one-word text equal to one reads as chrome, while a longer headline that opens with one stays
    # a headline, and a label followed by a year or a bare number stays a headline for every Norwegian-owned term.
    # It does not list what the shared tables already read on every scope (+kontakt+, +kontakt oss+, +om oss+,
    # +kommentarer+, +bli medlem+, +skriv en kommentar+), so each has one owner; those keep their shared reading
    # on a Norwegian page (+Om oss 2026+ and a headline that opens with +Om oss+ read as chrome). A term whose
    # precision is unclear is left out.
    No = Language.new(
      code: :no,
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
          'abonner på nyhetsbrev', 'abonner på nyhetsbrevet', 'meld deg på nyhetsbrev', 'meld deg på nyhetsbrevet',
          'tinga nyheitsbrev', 'meld deg på nyheitsbrevet', 'kjøp abonnement', 'tegn abonnement', 'bli abonnent',
          'opprett bruker gratis', 'skriv ein kommentar', 'skriv kommentar',
          'del artikkelen', 'del denne artikkelen', 'del artikkel'
        ],
        read_more: [
          'les mer', 'les mer her', 'les hele saken', 'les hele artikkelen', 'les videre', 'les resten',
          'les resten av saken', 'se mer', 'vis mer', 'les meir', 'les meir her', 'les heile saka',
          'les heile artikkelen', 'les vidare', 'les resten av saka', 'sjå meir', 'vis meir'
        ],
        list_more: [
          'se alle', 'vis alle', 'se flere', 'flere nyheter', 'flere saker', 'alle nyheter', 'alle saker',
          'se flere nyheter', 'se alle nyheter', 'se alle saker', 'vis flere', 'vis flere nyheter', 'sjå alle',
          'sjå fleire', 'fleire nyheiter', 'fleire saker', 'alle nyheiter', 'se fleire', 'vis fleire'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'åpnes i nytt vindu', 'åpner i nytt vindu', 'åpnes i ny fane', 'åpner i ny fane', 'åpne i nytt vindu',
          'åpne i ny fane', 'åpnes i et nytt vindu', 'åpnes i en ny fane', 'opnast i nytt vindauge',
          'opnar i nytt vindauge', 'opnast i ny fane', 'opnar i ny fane', 'opne i nytt vindauge', 'opne i ny fane'
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
          'logg inn', 'logg på', 'logg ut', 'opprett bruker', 'opprett brukar', 'opprett konto', 'registrer deg',
          'søk', 'tips oss', 'kundeservice', 'personvern', 'personvernerklæring',
          'personvernerklæringen', 'personvernpolicy', 'personverninnstillinger', 'personverninnstillingar',
          'cookieinnstillinger', 'cookie-innstillinger', 'cookieinnstillingar', 'informasjonskapsler',
          'vilkår og betingelser', 'brukervilkår', 'brukarvilkår', 'ofte stilte spørsmål', 'meny', 'lukk meny',
          'åpne meny', 'opne meny', 'forsiden', 'framsida', 'kommentarar', 'følg oss', 'min side',
          'min konto', 'hopp til innhold', 'hopp til hovedinnhold', 'hopp til hovedinnholdet', 'hopp til innhald',
          'hopp til hovudinnhald', 'gå til innhold', 'gå til hovedinnhold', 'gå til innhald', 'gå til hovudinnhald'
        ],
        recommended: [
          'relaterte artikler', 'relaterte artiklar', 'relaterte saker', 'relaterte nyheter', 'relaterte nyheiter',
          'les også', 'se også', 'sjå også', 'anbefalt for deg', 'anbefalte artikler', 'andre leste også',
          'andre las også', 'du vil kanskje også like'
        ]
      }.freeze
    )
  end
end
