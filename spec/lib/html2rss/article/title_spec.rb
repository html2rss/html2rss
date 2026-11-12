# frozen_string_literal: true

RSpec.describe Html2rss::Article::Title do
  describe '.collapse' do
    {
      "  Tram line\n extends\t" => 'Tram line extends',
      '10:00 Budget vote' => '10:00 Budget vote',
      'Video: Harbor tour' => 'Video: Harbor tour',
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
      [nil, '09:05'] => nil,
      [nil, nil] => nil
    }.each do |(headline, kicker), expected|
      it "composes #{headline.inspect} with kicker #{kicker.inspect} as #{expected.inspect}" do
        expect(described_class.compose(headline, kicker:)).to eq(expected)
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
        expect(described_class.compose(headline)).to eq(expected)
      end
    end

    it 'is idempotent on its own output' do
      title = described_class.compose('– 12:30 | Storm ahead', kicker: 'Rubrik: Weather :')

      expect(described_class.compose(title)).to eq(title)
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
  end

  describe '.headline_noise_piece?' do
    {
      '19:47' => true, '10:00 Uhr' => true, ' Section: ' => true, 'Rubrique :' => true, 'Article type: Video' => true,
      'Artikeltyp:' => true, 'Thema:' => true, 'Video' => false, 'Conflict:' => false, 'Section: Harbor' => false,
      '10:00 Budget vote' => false, '' => false, nil => false
    }.each do |text, expected|
      it "is #{expected} for #{text.inspect}" do
        expect(described_class.headline_noise_piece?(text)).to be(expected)
      end
    end
  end

  describe '.noise_piece?' do
    {
      'Thema:' => true, 'Thème :' => true, 'Tema:' => true, 'Topic:' => true, ' Section: ' => true, '19:47' => true,
      'Video' => true, 'Live Blog' => true, ' ' => true, nil => true, 'Verkehr' => false, 'Conflict:' => false,
      'Hafen-Streit:' => false, 'Thema: Verkehr' => false, '28:25' => false, 'Video tour' => false
    }.each do |text, expected|
      it "is #{expected} for #{text.inspect}" do
        expect(described_class.noise_piece?(text)).to be(expected)
      end
    end
  end
end
