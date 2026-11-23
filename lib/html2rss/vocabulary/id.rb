# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Indonesian. It is {PAGE_ONLY}: its terms apply on a page whose language resolves to +id+, and nowhere else, so
    # +:all+ and every other language read exactly what they read without it. Indonesian is written in Latin script and
    # its label words are ordinary words (+masuk+ is "enter", +daftar+ a list, +cari+ to look for), so no term is read
    # as a prefix or a substring: each label is listed whole and read as a whole text only (no trailing word, no
    # headline opener, see {LinkDestination::TextClassifier}). Only the concepts read through a {Scope} are listed
    # (label words, the call to action, read-more, recommended and the new-window notice); the others stay +NONE+ until
    # their readers take the page scope. It lists no type marker (stripping a short kicker could leave a headline below
    # the title floor), no section name (+nasional+, +bola+, +ekonomi+ and +otomotif+ are topics a feed may carry), no
    # pager label, no path word, and not the bare labels judged too likely to be a headline (+bantuan+ is aid, +iklan+
    # an advertisement, +redaksi+ the editorial staff, +berlangganan+ a subscription story). Some common words stay
    # listed as whole labels by judgment (+komentar+, +menu+, +cari+, +daftar+, +masuk+): a one-word text equal to one
    # reads as chrome, while a longer headline that opens with one stays a headline. A term whose precision is unclear
    # is left out.
    Id = Language.new(
      code: :id,
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
          'berlangganan newsletter', 'berlangganan buletin', 'berlangganan sekarang', 'langganan sekarang',
          'daftar newsletter', 'daftar buletin', 'daftar sekarang', 'daftar gratis', 'gabung sekarang',
          'tulis komentar', 'beri komentar', 'berikan komentar', 'bagikan artikel', 'bagikan artikel ini',
          'bagikan berita ini', 'bagikan tulisan ini'
        ],
        read_more: [
          'baca selengkapnya', 'baca lebih lanjut', 'baca artikel lengkap', 'baca berita selengkapnya',
          'baca artikel selengkapnya', 'baca lanjutannya', 'lanjutkan membaca', 'selengkapnya', 'lihat selengkapnya',
          'tonton selengkapnya'
        ],
        list_more: [
          'lihat semua', 'lihat semuanya', 'lihat lainnya', 'lihat lebih banyak', 'lihat berita lainnya',
          'berita lainnya', 'lainnya'
        ],
        topic_lead: NONE,
        topic_preposition: NONE,
        read_more_suffix: NONE,
        new_window_notice: [
          'buka di tab baru', 'buka di jendela baru', 'terbuka di tab baru', 'terbuka di jendela baru',
          'dibuka di tab baru', 'dibuka di jendela baru', 'membuka di tab baru', 'membuka di jendela baru'
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
          'masuk', 'masuk akun', 'daftar', 'daftar akun', 'keluar akun', 'cari', 'pencarian', 'tentang kami',
          'hubungi kami', 'kontak', 'kontak kami', 'pedoman media siber', 'pedoman siber', 'pasang iklan', 'info iklan',
          'kebijakan privasi', 'kebijakan cookie', 'pengaturan cookie', 'kelola cookie', 'syarat dan ketentuan',
          'syarat ketentuan', 'ketentuan layanan', 'ketentuan penggunaan', 'peta situs', 'pertanyaan umum',
          'pertanyaan yang sering diajukan', 'pusat bantuan', 'menu', 'tutup menu', 'buka menu', 'beranda',
          'halaman utama', 'komentar', 'bagikan', 'ikuti kami', 'lewati ke konten', 'langsung ke konten',
          'lompat ke konten', 'ke konten utama'
        ],
        recommended: [
          'berita terkait', 'artikel terkait', 'tulisan terkait', 'baca juga', 'baca lainnya',
          'rekomendasi untuk anda', 'rekomendasi untukmu', 'anda mungkin suka', 'anda mungkin juga suka',
          'anda mungkin menyukai', 'rekomendasi berita', 'rekomendasi artikel'
        ]
      }.freeze
    )
  end
end
