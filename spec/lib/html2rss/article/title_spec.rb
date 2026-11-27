# frozen_string_literal: true

RSpec.describe Html2rss::Article::Title do
  # Direction marks around a piece: LRM/RLM, ALM, RLE..PDF, RLI..PDI.
  bidi_wrappers = [[0x200F, 0x200F], [0x061C], [0x202B, 0x202C], [0x2067, 0x2069], [0x200E]].map do |codes|
    "#{[codes.first].pack('U')}%s#{[codes[1]].compact.pack('U*')}"
  end.freeze
  describe '.collapse' do
    it 'returns the title in NFC' do
      expect(described_class.collapse("Stra\u0308ße")).to eq("Str\u00E4ße")
    end

    {
      "  Tram line\n extends\t" => 'Tram line extends',
      '10:00 Budget vote' => '10:00 Budget vote',
      'Video: Harbor tour' => 'Video: Harbor tour',
      "Straßen\u00ADbahn" => 'Straßenbahn',
      "Zero\u200Bwidth\u2060 mark\uFEFF" => 'Zerowidth mark',
      "\u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645" => "\u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645",
      "\u{1F469}\u200D\u{1F4BB} Coders meet" => "\u{1F469}\u200D\u{1F4BB} Coders meet",
      "\uFEFF \u00AD " => nil,
      "  \n " => nil,
      nil => nil
    }.each do |text, expected|
      it "collapses #{text.inspect} to #{expected.inspect}" do
        expect(described_class.collapse(text)).to eq(expected)
      end
    end
  end

  describe '.compose' do
    {
      ['Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['Storm ahead', '  Weather  '] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather :'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather: '] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather |'] => 'Weather: Storm ahead',
      ['Storm ahead', '19:47 | Weather'] => 'Weather: Storm ahead',
      ['Storm ahead', '19:47 Uhr – Weather'] => 'Weather: Storm ahead',
      ['Storm ahead', '19:47 Weather'] => '19:47 Weather: Storm ahead',
      ['Storm ahead', 'Rubrik: Verkehr'] => 'Verkehr: Storm ahead',
      ['Storm ahead', 'Rubrique : Transports'] => 'Transports: Storm ahead',
      ['Storm ahead', 'Sección: Transporte'] => 'Transporte: Storm ahead',
      ['Storm ahead', 'Section: Harbor'] => 'Harbor: Storm ahead',
      ['Storm ahead', 'Artikel: Verkehr'] => 'Verkehr: Storm ahead',
      ['Storm ahead', '09:05'] => 'Storm ahead',
      ['Storm ahead', 'Video'] => 'Storm ahead',
      ['Storm ahead', '   '] => 'Storm ahead',
      ['Storm ahead', nil] => 'Storm ahead',
      ['Storm ahead', 'Storm'] => 'Storm ahead',
      %w[Storm storm] => 'Storm',
      ['storm ahead', 'Storm'] => 'storm ahead',
      ['Storm: ahead', 'Storm'] => 'Storm: ahead',
      ['Big storm ahead', 'Storm'] => 'Storm: Big storm ahead',
      ['Stormy weather', 'Storm'] => 'Storm: Stormy weather',
      %w[St Storm] => 'Storm: St',
      ['Storm ahead', 'Weather?'] => 'Weather? Storm ahead',
      ['Storm ahead', 'Weather!'] => 'Weather! Storm ahead',
      ['Storm ahead', 'Weather…'] => 'Weather… Storm ahead',
      ['Storm ahead', 'Weather? :'] => 'Weather? Storm ahead',
      ['Storm : ahead', 'Weather'] => 'Weather: Storm: ahead',
      ['- Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['– Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['— Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['/ Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['| Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['» Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['> Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      [': Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['· Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['• Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['› Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['→ Storm ahead', 'Weather'] => 'Weather: Storm ahead',
      ['–5 Grad in der Nacht', 'Wetter'] => 'Wetter: –5 Grad in der Nacht',
      ['-5 Grad in der Nacht', nil] => '-5 Grad in der Nacht',
      ['/e/ und /ə/: Vokale', nil] => '/e/ und /ə/: Vokale',
      ['> 50 Prozent heizen mit Gas', nil] => '> 50 Prozent heizen mit Gas',
      ['>50 Prozent heizen mit Gas', 'Energie'] => 'Energie: >50 Prozent heizen mit Gas',
      ['Storm ahead', 'Weather ›'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather →'] => 'Weather: Storm ahead',
      ['Storm ahead', '« Weather »'] => '« Weather »: Storm ahead',
      ['Storm ahead', 'Weather -'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather /'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather >'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather —'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather •'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Weather ·'] => 'Weather: Storm ahead',
      ['Storm ahead', '19:47 - Weather'] => 'Weather: Storm ahead',
      ['Storm ahead', 'Up-'] => 'Up-: Storm ahead',
      ['Storm ahead', 'A/'] => 'A/: Storm ahead',
      ['Storm ahead', '« Exclusif »'] => '« Exclusif »: Storm ahead',
      ['-5 degrees tonight', 'Weather'] => 'Weather: -5 degrees tonight',
      ['/r/ threads grow', 'Weather'] => 'Weather: /r/ threads grow',
      ['>Storm ahead', 'Weather'] => 'Weather: >Storm ahead',
      ['»Storm« ahead', 'Weather'] => 'Weather: »Storm« ahead',
      ['9:15 | Storm ahead', 'Weather'] => 'Weather: 9:15 | Storm ahead',
      [nil, 'Weather'] => 'Weather',
      [" \n ", 'Rubrik: Weather :'] => 'Weather',
      ['19:47', 'Weather'] => 'Weather: 19:47',
      [nil, 'Video'] => nil,
      ['【速報】政府、冬の除雪支援に3200億円支出へ', nil] => '政府、冬の除雪支援に3200億円支出へ',
      ['＜速報＞ 青空文化賞、第一回の受賞は画家の森野遥', nil] => '青空文化賞、第一回の受賞は画家の森野遥',
      ['【独自】新庁舎の案内動画、公開延期', nil] => '新庁舎の案内動画、公開延期',
      ['【動画】仮設宿泊施設', nil] => '仮設宿泊施設',
      ['【LIVE】首相会見', nil] => '首相会見',
      ['【Live】首相会見', nil] => '首相会見',
      ['【 LIVE 】首相会見', '政治'] => '政治: 首相会見',
      ['【 市長外交 】視察の日程', nil] => '市長外交: 視察の日程',
      ['【市長外交】視察、短い日程と多い訪問先', nil] => '市長外交: 視察、短い日程と多い訪問先',
      ['＜下＞ 連載の最終回', nil] => '下: 連載の最終回',
      ['【速報】政府が発表', '経済'] => '経済: 政府が発表',
      ['【市長外交】視察の日程', '政治'] => '政治: 【市長外交】視察の日程',
      ['【速報】', nil] => '【速報】',
      ['「速報」政府が発表', nil] => '「速報」政府が発表',
      ['首相会見【速報】', nil] => '首相会見【速報】',
      ['Pressemitteilung', '【速報】'] => 'Pressemitteilung',
      ['Il sindaco apre il museo', 'Diretta streaming'] => 'Il sindaco apre il museo',
      ['De burgemeester opent het museum', 'Persbericht'] => 'De burgemeester opent het museum',
      ['Premier otwiera muzeum', 'Relacja na żywo'] => 'Premier otwiera muzeum',
      ['Statsministern öppnar museet', 'Liverapport'] => 'Statsministern öppnar museet',
      ['Sezione: Il sindaco apre il museo', 'Cultura'] => 'Cultura: Sezione: Il sindaco apre il museo',
      [nil, '09:05'] => nil,
      [nil, nil] => nil
    }.each do |(headline, kicker), expected|
      it "composes #{headline.inspect} with kicker #{kicker.inspect} as #{expected.inspect}" do
        expect(described_class.compose(headline, kicker:, vocabulary: all_scope)).to eq(expected)
      end
    end

    {
      "Tram line extends\nto the eastern districts" => 'Tram line extends to the eastern districts',
      "  Tram line\t extends  " => 'Tram line extends',
      '9:15 | Park planting day' => '9:15 | Park planting day',
      '21:00:30 – Council approves' => '21:00:30 – Council approves',
      '9:15 PM • Council approves' => '9:15 PM • Council approves',
      '9:15pm · Council approves' => '9:15pm · Council approves',
      '9:15 Uhr: Bahnhof gesperrt' => '9:15 Uhr: Bahnhof gesperrt',
      '23:59 — Council approves' => '23:59 — Council approves',
      '10:00 Budget vote' => '10:00 Budget vote',
      '9:15 am Bahnhof gesperrt' => '9:15 am Bahnhof gesperrt',
      '9:155 trains cancelled' => '9:155 trains cancelled',
      '28:25 – Derby ends level' => '28:25 – Derby ends level',
      '24:00 | Night bus returns' => '24:00 | Night bus returns',
      '9:60 | Night bus returns' => '9:60 | Night bus returns',
      '12:30 | 10:00 – Council approves' => '12:30 | 10:00 – Council approves',
      ': Council approves' => 'Council approves',
      '– Council approves' => 'Council approves',
      '16:10 laptops are back' => '16:10 laptops are back',
      '23:21 – Handball women win' => '23:21 – Handball women win',
      '20:15 Uhr: Neuer Krimi' => '20:15 Uhr: Neuer Krimi',
      '9:41 is the time' => '9:41 is the time',
      '12:00 noon deadline passes' => '12:00 noon deadline passes',
      'Council approves —' => 'Council approves',
      'Council approves -' => 'Council approves',
      'Council approves »' => 'Council approves »',
      'Artikeltyp: Video Museum öffnet wieder' => 'Artikeltyp: Video Museum öffnet wieder',
      "Type d'article : Vidéo Le musée rouvre" => "Type d'article: Vidéo Le musée rouvre",
      'Tipo de artículo: Audio El museo reabre' => 'Tipo de artículo: Audio El museo reabre',
      'Article type: Live blog Council votes' => 'Article type: Live blog Council votes',
      'Article type: Council votes' => 'Article type: Council votes',
      'Category: Council votes' => 'Category: Council votes',
      'Video shows the new tram line' => 'Video shows the new tram line',
      'Council approves:' => 'Council approves',
      '2:1 win for the home side' => '2:1 win for the home side',
      %(Transit :\nTram line extends) => 'Transit: Tram line extends',
      'Transit :Tram line extends' => 'Transit: Tram line extends',
      'Transit : Tram line : east' => 'Transit: Tram line : east',
      'Ratio 3:2 for the east line' => 'Ratio 3:2 for the east line',
      '16 : 9 screens return' => '16 : 9 screens return',
      'Score 16 : 9 at the break' => 'Score 16 : 9 at the break',
      '"Quoted words" : Tram line extends' => '"Quoted words": Tram line extends',
      'Transit (east) : Tram line extends' => 'Transit (east): Tram line extends',
      'One two three four five six seven eight : Tram' => 'One two three four five six seven eight: Tram',
      'One two three four five six seven eight nine : Tram' => 'One two three four five six seven eight nine : Tram'
    }.each do |headline, expected|
      it "cleans #{headline.inspect} to #{expected.inspect}" do
        expect(described_class.compose(headline, vocabulary: all_scope)).to eq(expected)
      end
    end

    it 'keeps the space before a colon on a French page and closes it elsewhere', :aggregate_failures do
      french = Html2rss::Vocabulary[:fr]
      headline = "Lyon\u00A0: la saison reprend"

      expect(described_class.compose(headline, vocabulary: french)).to eq('Lyon : la saison reprend')
      expect(described_class.compose(headline, vocabulary: Html2rss::Vocabulary[:en])).to eq('Lyon: la saison reprend')
    end

    it 'closes a spaced colon inside a kicker off French pages only', :aggregate_failures do
      en = described_class.compose('Council votes', kicker: 'Big storm : Weather', vocabulary: Html2rss::Vocabulary[:en])
      fr = described_class.compose('Council votes', kicker: 'Big storm : Weather', vocabulary: Html2rss::Vocabulary[:fr])

      expect(en).to eq('Big storm: Weather: Council votes')
      expect(fr).to eq('Big storm : Weather: Council votes')
    end

    it 'is idempotent on its own output' do
      title = described_class.compose('– 12:30 | Storm ahead', kicker: 'Rubrik: Weather :', vocabulary: all_scope)

      expect(described_class.compose(title, vocabulary: all_scope)).to eq(title)
    end

    it 'drops a kicker that is only a marker wrapped in marks and keeps the headline verbatim' do
      rlm = [0x200F].pack('U')
      headline = "#{rlm}Headline#{rlm}"
      expect(described_class.compose(headline, kicker: "#{rlm}Video#{rlm}", vocabulary: all_scope)).to eq(headline)
    end

    it 'keeps a ZWNJ inside a Persian word, and the marks, in the output' do
      rlm = [0x200F].pack('U')
      kicker = "#{rlm}kicker#{rlm}"
      zwnj = [0x200C].pack('U')
      expect(described_class.compose("a#{zwnj}b", kicker:, vocabulary: all_scope)).to eq("#{kicker}: a#{zwnj}b")
    end

    it 'composes a blank bracket label as before, without raising', :aggregate_failures do
      expect(described_class.compose('【 】Headline', vocabulary: all_scope)).to eq(' : Headline')
      expect(described_class.compose("＜\u3000＞Headline", vocabulary: all_scope)).to eq(' : Headline')
    end
  end

  describe '.clock_piece?' do
    {
      '19:47' => true, ' 9:05 ' => true, '10:00 CET' => true, '10:00 Uhr' => true, '9:15pm' => true,
      '10:00 Europe/Berlin' => true, '10:00 GMT+1' => true,
      '28:25' => false, '10:00 Budget vote' => false, 'Weather' => false, '' => false, nil => false
    }.each do |text, expected|
      it "is #{expected} for #{text.inspect}" do
        expect(described_class.clock_piece?(text)).to be(expected)
      end
    end

    bidi_wrappers.each do |wrapper|
      it "reads a clock wrapped in #{wrapper.inspect}" do
        expect(described_class.clock_piece?(format(wrapper, '10:00'))).to be(true)
      end
    end

    it 'reads a clock set off from its marks by spaces' do
      expect(described_class.clock_piece?("#{[0x200F].pack('U')} 10:00 #{[0x200F].pack('U')}")).to be(true)
    end
  end

  describe '.headline_noise_piece?' do
    {
      '19:47' => true, '10:00 Uhr' => true, ' Section: ' => true, 'Rubrique :' => true, 'Article type: Video' => true,
      'Artikeltyp:' => true, 'Thema:' => true, 'Sezione:' => true, 'Onderwerp :' => true, 'Dział:' => true,
      'Ämne:' => true, 'カテゴリー：' => true, 'Tipo di articolo: Video' => true, 'Artikeltype: Persbericht' => true,
      'Typ artykułu: Galeria' => true, 'Innehållstyp: Bildspel' => true, '記事の種類：動画' => true,
      '11月12日 16:42' => true, '2026年11月12日' => true, '11月12日' => true, '11月12日の会見' => false,
      'Article:' => true, 'Artikel :' => true, 'Artículo:' => true, 'Articolo:' => true, 'Artykuł:' => true,
      '記事：' => true, 'Article' => false, 'Article: Harbor' => false, 'Articles:' => false,
      'Video' => false, 'Conflict:' => false, 'Section: Harbor' => false,
      '10:00 Budget vote' => false, '' => false, nil => false
    }.each do |text, expected|
      it "is #{expected} for #{text.inspect}" do
        expect(described_class.headline_noise_piece?(text, vocabulary: all_scope, date_element: false)).to be(expected)
      end
    end

    bidi_wrappers.each do |wrapper|
      it "reads a date and a label wrapped in #{wrapper.inspect}", :aggregate_failures do
        expect(described_class.headline_noise_piece?(format(wrapper, '11月12日 16:42'), vocabulary: all_scope,
                                                                                      date_element: false)).to be(true)
        expect(described_class.headline_noise_piece?(format(wrapper, 'Section:'), vocabulary: all_scope,
                                                                                  date_element: false)).to be(true)
      end
    end
  end

  describe '.date_piece?' do
    {
      '11月12日 16:42' => true, '2026年11月12日' => true, ' 11月9日 ' => true, '11月12日 政府' => false,
      '16:42' => false, 'November 12' => false, nil => false
    }.each do |text, expected|
      it "is #{expected} for #{text.inspect}" do
        expect(described_class.date_piece?(text, vocabulary: all_scope, date_element: false)).to be(expected)
      end
    end

    bidi_wrappers.each do |wrapper|
      it "reads a date wrapped in #{wrapper.inspect}" do
        expect(described_class.date_piece?(format(wrapper, '11月12日'), vocabulary: all_scope,
                                                                      date_element: false)).to be(true)
      end
    end
  end

  describe '.headline_noise_piece? with accented labels in any case and Unicode form' do
    labels = ['Ämne:', 'ÄMNE:', 'CATÉGORIE :', 'THÈME:', 'SECCIÓN:', 'CATEGORÍA:', 'DZIAŁ:', 'ARTYKUŁ:',
              'TIPO DE ARTÍCULO: Video', 'TYP TREŚCI: Galeria', 'ARTÍCULO:']

    forms = %i[nfc nfd]

    labels.each do |label|
      forms.each do |form|
        it "treats #{label.inspect} in #{form} as a label piece" do
          text = label.unicode_normalize(form)

          expect([described_class.headline_noise_piece?(text, vocabulary: all_scope, date_element: false),
                  described_class.noise_piece?(text, vocabulary: all_scope)]).to eq([true, true])
        end
      end
    end

    it 'composes the same title from a decomposed and a composed kicker label' do
      decomposed = described_class.compose('Hafen', kicker: "A\u0308mne: Verkehr", vocabulary: all_scope)

      expect(decomposed).to eq(described_class.compose('Hafen', kicker: "\u00C4mne: Verkehr", vocabulary: all_scope))
    end
  end

  describe '.noise_piece?' do
    {
      'Thema:' => true, 'Thème :' => true, 'Tema:' => true, 'Topic:' => true, ' Section: ' => true, '19:47' => true,
      'Video' => true, 'Live Blog' => true, 'Diretta streaming' => true, 'Persbericht' => true,
      'Na żywo' => true, 'Liverapport' => true, '速報' => true, 'プレスリリース' => true, 'Sezione:' => true,
      'Ämne:' => true, 'セクション：' => true, 'Article:' => true, 'Artikel:' => true, 'Artículo :' => true,
      ' ' => true, nil => true, 'Verkehr' => false, 'Conflict:' => false,
      'Hafen-Streit:' => false, 'Thema: Verkehr' => false, 'Artikel' => false, '28:25' => false, 'Video tour' => false
    }.each do |text, expected|
      it "is #{expected} for #{text.inspect}" do
        expect(described_class.noise_piece?(text, vocabulary: all_scope)).to be(expected)
      end
    end

    bidi_wrappers.each do |wrapper|
      it "reads a marker, label and clock wrapped in #{wrapper.inspect}", :aggregate_failures do
        expect(described_class.noise_piece?(format(wrapper, 'Video'), vocabulary: all_scope)).to be(true)
        expect(described_class.noise_piece?(format(wrapper, 'Section:'), vocabulary: all_scope)).to be(true)
        expect(described_class.noise_piece?(format(wrapper, '10:00'), vocabulary: all_scope)).to be(true)
        expect(described_class.noise_piece?(format(wrapper, 'Conflict'), vocabulary: all_scope)).to be(false)
      end
    end

    it 'reads marks set off by spaces, and marks alone, like the clean form', :aggregate_failures do
      rlm = [0x200F].pack('U')
      expect(described_class.noise_piece?("#{rlm} Video", vocabulary: all_scope)).to be(true)
      expect(described_class.noise_piece?("#{rlm} 10:00 #{rlm}", vocabulary: all_scope)).to be(true)
      expect(described_class.noise_piece?(rlm, vocabulary: all_scope)).to be(true)
    end
  end

  describe 'Han type markers on a Chinese page' do
    let(:chinese) { %w[zh zh-Hant zh-Hans-CN ZH_tw].map { Html2rss::Vocabulary[_1] } }
    let(:others) { ['ja', 'ja-JP', 'en', 'de', 'zh-', 'xx', nil, :all].map { Html2rss::Vocabulary[_1] } }

    {
      '独自' => '独自: 見出しの本文',
      '写真' => '写真: 見出しの本文'
    }.each do |marker, composed|
      it "keeps #{marker} as kicker text on a Chinese page and drops it as a marker elsewhere", :aggregate_failures do
        expect(chinese.map { described_class.compose('見出しの本文', kicker: marker, vocabulary: _1) }).to all(eq(composed))
        expect(others.map { described_class.compose('見出しの本文', kicker: marker, vocabulary: _1) })
          .to all(eq('見出しの本文'))
        expect(described_class.compose('見出しの本文', kicker: marker, vocabulary: all_scope)).to eq('見出しの本文')
      end
    end

    it 'reads a leading bracket naming one of them as the kicker on a Chinese page', :aggregate_failures do
      expect(chinese.map { described_class.compose('【独自】政府が発表', vocabulary: _1) }).to all(eq('独自: 政府が発表'))
      expect(chinese.map { described_class.compose('＜写真＞海辺の町', vocabulary: _1) }).to all(eq('写真: 海辺の町'))
      expect(others.map { described_class.compose('【独自】政府が発表', vocabulary: _1) }).to all(eq('政府が発表'))
      expect(described_class.compose('＜写真＞海辺の町', vocabulary: all_scope)).to eq('海辺の町')
    end

    it 'keeps a bracket marker inside a kicker as noise only where it is a marker', :aggregate_failures do
      expect(described_class.compose('見出し本文', kicker: '【独自】', vocabulary: all_scope)).to eq('見出し本文')
      expect(described_class.compose('見出し本文', kicker: '【独自】', vocabulary: Html2rss::Vocabulary['zh']))
        .to eq('【独自】: 見出し本文')
    end

    it 'judges a kicker piece with the page language', :aggregate_failures do
      expect(chinese.map { described_class.noise_piece?('独自', vocabulary: _1) }).to all(be(false))
      expect(chinese.map { described_class.noise_piece?(' 写真 ', vocabulary: _1) }).to all(be(false))
      expect(others.map { described_class.noise_piece?('独自', vocabulary: _1) }).to all(be(true))
      expect(described_class.noise_piece?('写真', vocabulary: all_scope)).to be(true)
    end

    it 'keeps every other marker a marker on a Chinese page', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      zh = Html2rss::Vocabulary['zh']
      readings = lambda do |marker|
        [described_class.noise_piece?(marker, vocabulary: zh),
         described_class.compose('見出しの本文', kicker: marker, vocabulary: zh),
         described_class.compose("【#{marker}】見出し", vocabulary: zh)]
      end

      (described_class::TYPE_MARKERS - Html2rss::Vocabulary::Zh.plain_words).each do |marker|
        expect(readings.call(marker)).to eq([true, '見出しの本文', '見出し']), marker
      end
    end

    it 'keeps a type label with its marker noise on a Chinese page, since the label is Japanese itself' do
      expect(described_class.compose('見出しの本文', kicker: '記事の種類：独自', vocabulary: Html2rss::Vocabulary['zh']))
        .to eq('見出しの本文')
    end

    it 'leaves every non-Han marker and label alone on a Chinese page', :aggregate_failures do
      zh = Html2rss::Vocabulary['zh']
      expect(described_class.compose('Haven', kicker: 'Video', vocabulary: zh)).to eq('Haven')
      expect(described_class.compose('Haven', kicker: 'Thema: Verkehr', vocabulary: zh)).to eq('Verkehr: Haven')
      expect(described_class.noise_piece?('Live Blog', vocabulary: zh)).to be(true)
    end
  end

  shared_context 'with a page-only title language' do
    let(:xx) do
      terms = Html2rss::Vocabulary::CONCEPTS.to_h { [_1, Html2rss::Vocabulary::NONE] }
      terms.merge!(field_label: %w[rubriek-xx], type_label: %w[soort-xx], clock_suffix: %w[uur-xx],
                   date_piece: [/\d{1,2}-mnd-xx|\d{1,2}:\d{2}/])
      language = Html2rss::Vocabulary::Language.new(code: :xx, terms: terms.freeze)
      Html2rss::Vocabulary.build_scope(:zh, Html2rss::Vocabulary::SHARED_LANGUAGES, own: [language])
    end
    let(:own_only) { { vocabulary: xx, date_element: true } }

    # The scope table is closed at load, so the simulated language joins it for the example.
    before do
      own = described_class::OWN_CONCEPTS.to_h { [_1, xx.own_alternation(_1)] }
      table = described_class.const_get(:RULES_BY_SCOPE).merge(zh: described_class::Rules.build(xx.type_markers, own))
      stub_const("#{described_class}::RULES_BY_SCOPE", table)
    end
  end

  describe '.compose with a page-only language' do
    include_context 'with a page-only title language'

    it 'strips an own label and clock suffix from a kicker, and no one else does', :aggregate_failures do
      expect(described_class.compose('Haven', kicker: 'Rubriek-xx: Sport', vocabulary: xx)).to eq('Sport: Haven')
      expect(described_class.compose('Haven', kicker: '10:30 uur-xx | Sport', vocabulary: xx)).to eq('Sport: Haven')
      expect(described_class.compose('Haven', kicker: 'Soort-xx: Video Sport', vocabulary: xx)).to eq('Sport: Haven')
      expect(described_class.compose('Haven', kicker: 'Rubriek-xx: Sport', vocabulary: all_scope))
        .to eq('Rubriek-xx: Sport: Haven')
    end

    it 'never empties a title: a kicker that is only an own label stays', :aggregate_failures do
      expect(described_class.compose(nil, kicker: 'Rubriek-xx:', vocabulary: xx)).to eq('Rubriek-xx')
      expect(described_class.compose(nil, kicker: 'Rubriek-xx:', vocabulary: all_scope)).to eq('Rubriek-xx')
      expect(described_class.compose(nil, kicker: 'Soort-xx : Rubriek-xx:', vocabulary: xx))
        .to eq('Soort-xx: Rubriek-xx')
      expect(described_class.compose(nil, kicker: nil, vocabulary: xx)).to be_nil
    end
  end

  describe '.noise_piece? and .date_piece? with a page-only language' do
    include_context 'with a page-only title language'

    it 'reads an own label as a whole piece, an own date only as a standalone chip', :aggregate_failures do
      expect(described_class.noise_piece?('Soort-xx:', vocabulary: xx)).to be(true)
      expect(described_class.noise_piece?('Soort-xx:', vocabulary: all_scope)).to be(false)
      expect(described_class.date_piece?('12-mnd-xx', **own_only)).to be(true)
      expect(described_class.date_piece?('12-mnd-xx', vocabulary: xx, date_element: false)).to be(false)
      expect(described_class.date_piece?('12-mnd-xx', vocabulary: all_scope, date_element: true)).to be(false)
    end
  end

  describe '.own_noise_piece? with a page-only language' do
    include_context 'with a page-only title language'

    it 'tells a piece that is noise only through an own term', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(described_class.own_noise_piece?('12-mnd-xx', **own_only)).to be(true)
      expect(described_class.own_noise_piece?('Soort-xx:', vocabulary: xx, date_element: false)).to be(true)
      expect(described_class.own_noise_piece?('10:30', **own_only)).to be(false)
      expect(described_class.own_noise_piece?('Section:', **own_only)).to be(false)
      expect([nil, '', '  '].map { described_class.own_noise_piece?(_1, **own_only) }).to all(be(false))
      expect(described_class.own_noise_piece?('Soort-xx:', vocabulary: all_scope, date_element: true)).to be(false)
    end

    it 'reads bidi marks around the piece and no own term in a scope without any', :aggregate_failures do
      rlm = [0x200F].pack('U')

      expect(described_class.own_noise_piece?("#{rlm}Soort-xx:#{rlm}", vocabulary: xx, date_element: false)).to be(true)
      expect(described_class.own_noise_piece?('Soort-xx:', vocabulary: Html2rss::Vocabulary[:en], date_element: false))
        .to be(false)
    end
  end
end
