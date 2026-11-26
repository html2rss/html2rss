# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Turkish. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +tr+, and nowhere else. Turkish
    # attaches suffixes to nouns ("girişimcilerin", "iletişimde"), so no term is read as a prefix or a substring: each
    # label is listed whole, read as a whole text only (no trailing word, no headline opener, see
    # {AutoSource::LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed (label words,
    # the call
    # to action, read-more, recommended and the new-window notice); the others stay +NONE+ until their readers take
    # the page scope. It lists no type marker (stripping a short kicker could leave a headline below the title floor),
    # no section name (+gündem+, +spor+ and +ekonomi+ are topics a feed may carry), no pager label, no path word, and
    # no label that is also a plausible short headline (+giriş+ is an introduction, +çıkış+ an exit, +bülten+ a news
    # bulletin, +yardım+ aid, +abonelik+ a subscription story, +ara+ a pause). A term whose precision is unclear is
    # left out.
    #
    # Turkish has a dotted and a dotless i, and the case-insensitive match folds neither pair: +İ+ does not match
    # +i+ and +ı+ does not match +I+ ("GİRİŞ YAP" and "ÇIKIŞ YAP" match no lowercase term). Each label is written in
    # lowercase and expanded below into one fragment per concept, so every +i+ also reads +İ+ and every +ı+ also
    # reads +I+. Because +I+ folds to +i+, a label with a dotless i also reads its dotted spelling ("hakkimizda"),
    # while a label typed without its other Turkish letters ("Iletisim", "CIKIS YAP") is not read.
    Tr = Language.new(
      code: :tr,
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
          'bültene abone ol', 'bültenimize abone ol', 'bültenimize abone olun', 'e-bültene abone ol',
          'e-bültene kayıt ol', 'e-bültene kaydol', 'e-bültene abone olun', 'şimdi abone ol', 'hemen abone ol',
          'ücretsiz abone ol', 'abone ol', 'abone olun', 'yorum yap', 'yorum yaz', 'haberi paylaş', 'bu haberi paylaş',
          'bu yazıyı paylaş', 'makaleyi paylaş', 'hemen üye ol', 'ücretsiz üye ol'
        ],
        read_more: [
          'devamını oku', 'devamını okuyun', 'devamı', 'haberin devamı', 'yazının devamı', 'daha fazla oku',
          'tamamını oku', 'haberin tamamını oku', 'haberi oku', 'yazının tamamını oku', 'devamı için tıklayın',
          'okumaya devam et', 'okumaya devam edin'
        ],
        list_more: [
          'daha fazla', 'daha fazlası', 'daha fazla göster', 'tümünü gör', 'tümünü göster', 'hepsini gör'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'yeni sekmede açılır', 'yeni pencerede açılır', 'yeni sekmede aç', 'yeni pencerede aç',
          'yeni sekmede açar', 'yeni pencerede açar'
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
          'giriş yap', 'giriş yapın', 'oturum aç', 'oturum açın', 'üye girişi', 'kullanıcı girişi', 'çıkış yap',
          'çıkış yapın', 'oturumu kapat', 'kayıt ol', 'kaydol', 'üye ol', 'arama', 'hakkımızda', 'iletişim',
          'bize ulaşın', 'bize yazın', 'künye', 'reklam ver', 'gizlilik politikası', 'gizlilik sözleşmesi',
          'gizlilik bildirimi', 'çerez politikası', 'çerez ayarları', 'çerez tercihleri', 'çerezleri yönet', 'kvkk',
          'aydınlatma metni', 'kullanım koşulları', 'kullanım şartları', 'kullanım sözleşmesi', 'şartlar ve koşullar',
          'site haritası', 'sıkça sorulan sorular', 'yardım merkezi', 'menü', 'ana sayfa', 'anasayfa', 'yorumlar',
          'paylaş', 'içeriğe geç', 'içeriğe atla', 'ana içeriğe geç', 'ana içeriğe atla'
        ],
        recommended: [
          'ilgili haberler', 'ilgili yazılar', 'ilgili içerikler', 'ilgili makaleler', 'benzer haberler',
          'benzer yazılar', 'önerilen haberler', 'önerilen yazılar', 'bunlar da ilginizi çekebilir',
          'ilginizi çekebilir', 'bunları da okuyun', 'bunu da oku', 'sizin için seçtiklerimiz'
        ]
      }.transform_values do |labels|
        fold = ->(word) { word.gsub('i', '(?:i|İ)').gsub('ı', '(?:ı|I)') }
        labels.empty? ? labels : [Regexp.new(labels.map { _1.split.map(&fold).join('\s+') }.join('|'))]
      end.freeze
    )
  end
end
