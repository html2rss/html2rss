# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Hungarian. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +hu+, and nowhere else.
    # Hungarian is agglutinative, so each label form a site really writes is listed whole (+hozzászólás+ and
    # +hozzászólások+, +iratkozzon fel+ and +iratkozz fel+), never stemmed. No term is read as a prefix or a substring:
    # each label is read as a whole text only (no trailing word, no headline opener, see
    # {LinkDestination::TextClassifier}). Terms are written in NFC, the form the classifier normalizes to, so
    # decomposed input matches and upper case ("BEJELENTKEZÉS", "HÍRLEVÉL") folds, +ő+ and +ű+ included. Only
    # the concepts read through a {Scope} are listed (label words, the call to action, read-more, recommended and
    # the new-window notice); the others stay +NONE+ until their readers take the page scope. It lists no type
    # marker (stripping a short kicker could leave a headline below the title floor), no section name (+belföld+,
    # +külföld+, +sport+, +gazdaság+ and +vélemény+ are topics a feed may carry), no pager label, no path word, and
    # not the bare labels judged too likely to be a headline (+hirdetés+ is an advertisement, +támogatás+ a
    # subsidy, +profil+ a profile piece, +folytatás+ a sequel, +részletek+ details, +karrier+ a career story,
    # +előfizetés+ a subscription story). Some common words stay listed as whole labels by judgment (+menü+,
    # +keresés+, +kapcsolat+, +tovább+): a one-word text equal to one reads as chrome, while a longer
    # headline that opens with one stays a headline. It lists no list-level more or see-all label (+összes hír+,
    # +további hírek+, +még több cikk+) as chrome, because as a card's only link it would empty the feed; they are
    # +list_more+ terms. A term whose precision is unclear is left out.
    Hu = Language.new(
      code: :hu,
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
          'iratkozzon fel hírlevelünkre', 'iratkozz fel hírlevelünkre', 'iratkozzon fel a hírlevélre',
          'iratkozz fel a hírlevélre', 'feliratkozom a hírlevélre', 'feliratkozás a hírlevélre', 'hozzászólás írása',
          'szólj hozzá a cikkhez', 'szóljon hozzá a cikkhez', 'cikk megosztása', 'oszd meg a cikket',
          'ossza meg a cikket', 'oszd meg ezt a cikket', 'ossza meg ezt a cikket'
        ],
        read_more: [
          'tovább', 'bővebben', 'olvass tovább', 'olvasson tovább', 'olvasd tovább', 'olvassa tovább', 'tovább olvasom',
          'tovább a cikkhez', 'tovább a cikkre', 'tovább a teljes cikkhez', 'teljes cikk', 'a teljes cikk',
          'teljes cikk elolvasása', 'cikk elolvasása', 'elolvasom a cikket', 'tudj meg többet', 'tudjon meg többet',
          'további részletek', 'részletek megtekintése', 'bővebb információ', 'a cikk folytatása', 'cikk folytatása'
        ],
        list_more: [
          'összes', 'összes megtekintése', 'összes hír', 'összes friss hír', 'összes cikk', 'mutasd mindet',
          'még több hír', 'még több cikk', 'további hírek', 'további cikkek', 'további cikkeink', 'további epizódok',
          'további tartalmak', 'tovább a rovatra'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'új ablakban nyílik meg', 'új lapon nyílik meg', 'új fülön nyílik meg', 'új ablakban nyílik',
          'új lapon nyílik', 'új fülön nyílik', 'megnyitás új ablakban', 'megnyitás új lapon',
          'megnyitás új fülön'
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
          'belépés', 'bejelentkezés', 'kijelentkezés', 'kilépés', 'regisztráció', 'regisztrálok', 'fiók létrehozása',
          'elfelejtett jelszó', 'keresés', 'rólunk', 'magunkról', 'impresszum', 'kapcsolat', 'kapcsolatfelvétel',
          'elérhetőségek', 'médiaajánlat', 'hirdetési lehetőségek', 'hirdetésfelvétel', 'hirdetési ászf', 'ászf',
          'általános szerződési feltételek', 'szerződési feltételek', 'felhasználási feltételek',
          'felhasználói feltételek', 'használati feltételek', 'adatvédelmi tájékoztató', 'adatvédelmi nyilatkozat',
          'adatvédelmi szabályzat', 'adatvédelmi irányelvek', 'adatkezelési tájékoztató', 'adatkezelési szabályzat',
          'adatkezelési nyilatkozat', 'süti beállítások', 'sütibeállítások', 'cookie beállítások', 'cookie-beállítások',
          'süti szabályzat', 'sütik kezelése', 'cookie-k kezelése', 'cookie szabályzat', 'cookie-szabályzat',
          'jogi nyilatkozat', 'jogi közlemény', 'moderálási szabályzat', 'oldaltérkép', 'honlaptérkép',
          'gyakran ismételt kérdések', 'gyik', 'hírlevél', 'iratkozzon fel', 'iratkozz fel', 'feliratkozás',
          'feliratkozom', 'menü', 'menü megnyitása', 'menü bezárása', 'főmenü', 'címlap', 'kezdőlap', 'főoldal',
          'vissza a címlapra', 'vissza a főoldalra', 'ugrás a tartalomhoz', 'ugrás a tartalomra',
          'ugrás a főtartalomhoz', 'ugrás a fő tartalomhoz', 'hozzászólás', 'hozzászólások', 'komment', 'kommentek',
          'megosztás', 'megosztom', 'kövess minket', 'kövessen minket', 'alkalmazás letöltése',
          'töltsd le az alkalmazást'
        ],
        recommended: [
          'kapcsolódó cikkek', 'kapcsolódó hírek', 'kapcsolódó tartalmak', 'kapcsolódó cikkeink', 'ajánlott cikkek',
          'ajánlott hírek', 'ajánlott tartalmak', 'hasonló cikkek', 'hasonló hírek', 'ajánljuk még', 'ezt is ajánljuk',
          'olvasd el ezt is', 'olvassa el ezt is', 'olvasd még', 'ez is érdekelhet', 'ez is érdekelheti',
          'neked ajánljuk', 'önnek ajánljuk', 'ajánlott olvasmányok'
        ]
      }.freeze
    )
  end
end
