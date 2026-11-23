# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Danish. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +da+, and nowhere else, so
    # +:all+ and every other language read exactly what they read without it. Danish is written in Latin script and
    # its label words are ordinary words (+søg+ is "search", +kontakt+ "contact", +læs+ "read"), so no term is read
    # as a prefix or a substring: each label is listed whole and read as a whole text only (no trailing word, no
    # headline opener, see {LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed
    # (label words, the call to action, read-more, recommended and the new-window notice); the others stay +NONE+
    # until their readers take the page scope. It lists no type marker (stripping a short kicker could leave a
    # headline below the title floor), no section name (+udland+, +kultur+, +debat+ and +erhverv+ are topics a feed
    # may carry), no pager label, no path word, and not the bare labels judged too likely to be a headline (+del+ is
    # a part of a series, +hjælp+ is aid, +annoncering+ advertising, +lyt+ an imperative that opens headlines,
    # +seneste nyt+ and +mest læste+ are sections, +se alle+, +se flere+ and +flere nyheder+ are list-level "more"
    # labels that would empty a card whose only link carries one; +vis mere+ is listed as a read-more label). Some
    # common words stay listed as whole labels by judgment (+kontakt+, +søg+, +menu+, +kommentarer+): a one-word
    # text equal to one reads as chrome, while a longer headline that opens with one stays a headline, and a
    # label followed by a year or a bare number stays a headline for every Danish-owned term. The exception is
    # +kontakt+ and +kommentarer+, which also keep the German, Polish and Swedish readings every scope shares, so
    # +Kontakt 2026+, +Kommentarer 2026+, +Kontakt Danmark 2026+ and +Kommentarer fra 2026+ read as chrome. A term
    # whose precision is unclear is left out.
    Da = Language.new(
      code: :da,
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
          'tilmeld dig nyhedsbrev', 'tilmeld dig nyhedsbrevet', 'tilmeld dig vores nyhedsbrev',
          'tilmeld nyhedsbrev', 'køb abonnement', 'tegn abonnement', 'bliv abonnent', 'bliv medlem',
          'opret bruger gratis', 'skriv en kommentar', 'skriv kommentar', 'del artiklen', 'del denne artikel',
          'del artikel'
        ],
        read_more: [
          'læs mere', 'læs mere her', 'læs hele artiklen', 'læs hele historien', 'læs videre', 'læs resten',
          'læs resten af artiklen', 'læs flere', 'se mere', 'vis mere'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'åbner i nyt vindue', 'åbner i et nyt vindue', 'åbner i ny fane', 'åbner i en ny fane',
          'åbnes i nyt vindue', 'åbnes i et nyt vindue', 'åbnes i ny fane', 'åbnes i en ny fane',
          'åbn i nyt vindue', 'åbn i ny fane'
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
          'log ind', 'log på', 'log ud', 'opret bruger', 'opret konto', 'søg', 'søgning', 'kontakt', 'kontakt os',
          'om os', 'tip os', 'kundeservice', 'privatlivspolitik', 'persondatapolitik', 'cookiepolitik',
          'cookieindstillinger', 'cookie-indstillinger', 'vilkår og betingelser', 'handelsbetingelser',
          'brugerbetingelser', 'ofte stillede spørgsmål', 'menu', 'luk menu', 'åbn menu', 'forside', 'kommentarer',
          'følg os', 'spring til indhold', 'gå til indhold', 'gå til hovedindhold'
        ],
        recommended: [
          'relaterede artikler', 'relaterede historier', 'relaterede nyheder', 'læs også', 'se også',
          'anbefalet til dig', 'anbefalede artikler', 'andre læste også', 'du vil måske også kunne lide'
        ]
      }.freeze
    )
  end
end
