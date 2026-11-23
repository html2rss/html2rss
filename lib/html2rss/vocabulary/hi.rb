# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Hindi in Devanagari. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +hi+,
    # and nowhere else. Hindi attaches postpositions and verbs to nouns ("लॉगिन समस्या से यूजर परेशान",
    # "सदस्यता अभियान शुरू"), so no term is read as a prefix: each label form is listed whole and read as
    # a whole text only (no trailing word, no headline opener, see {LinkDestination::TextClassifier}).
    # Terms are written in NFC, the form the classifier normalizes a link text to: a precomposed nukta
    # letter (U+095C, U+095D, U+095B ...) is a composition exclusion, so +ड़+ is +ड+ and a nukta sign, and
    # the spec rejects a term that is not NFC. Variant spellings of one label ("लॉग इन", "लॉगिन") are
    # listed apart. Romanized Hindi is not covered. Only the concepts read through a {Scope} are listed;
    # the others stay +NONE+ until their readers take the page scope. It lists no type marker (stripping a
    # short kicker could leave a headline below the title floor) and no section name (+खेल+, +देश+ and
    # +राशिफल+ are topics a feed may carry). A term whose precision is unclear (+शेयर+ is also the stock
    # share, +पढ़ें+ and +देखें+ open headlines) is left out.
    Hi = Language.new(
      code: :hi,
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
          'सब्सक्राइब करें', 'अभी सब्सक्राइब करें', 'न्यूज़लेटर सब्सक्राइब करें', 'सदस्यता लें', 'अभी सदस्यता लें',
          'साइन इन करें', 'लॉग इन करें', 'लॉगिन करें', 'रजिस्टर करें', 'पंजीकरण करें', 'शेयर करें', 'कमेंट करें'
        ],
        read_more: [
          'और पढ़ें', 'और देखें', 'और जानें', 'अधिक पढ़ें', 'अधिक जानें', 'आगे पढ़ें', 'पूरी खबर पढ़ें',
          'पूरी ख़बर पढ़ें', 'पूरा पढ़ें', 'विस्तार से पढ़ें', 'विस्तार में पढ़ें'
        ],
        list_more: NONE,
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [/नई\s*(?:विंडो|टैब)\s*में\s*(?:खुलता\s*है|खुलेगा|खोलें)/],
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
          'लॉग इन', 'लॉगिन', 'लॉग आउट', 'लॉगआउट', 'साइन इन', 'साइन अप', 'साइनअप', 'रजिस्टर', 'सर्च', 'खोजें',
          'मेन्यू', 'मेनू', 'संपर्क करें', 'हमसे संपर्क करें', 'हमारे बारे में', 'हमसे जुड़ें', 'गोपनीयता नीति',
          'प्राइवेसी पॉलिसी', 'उपयोग की शर्तें', 'इस्तेमाल की शर्तें', 'नियम और शर्तें', 'विज्ञापन दें', 'साइटमैप',
          'कुकी नीति', 'सहायता', 'न्यूज़लेटर', 'सदस्यता', 'बंद करें'
        ],
        recommended: [
          'संबंधित खबरें', 'संबंधित ख़बरें', 'संबंधित खबर', 'संबंधित समाचार', 'संबंधित लेख', 'सम्बंधित खबरें',
          'यह भी पढ़ें', 'ये भी पढ़ें', 'इन्हें भी पढ़ें'
        ]
      }.freeze
    )
  end
end
