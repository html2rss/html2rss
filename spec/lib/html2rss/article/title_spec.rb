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
      ['Storm ahead', '19:47 Weather'] => 'Weather: Storm ahead',
      ['Storm ahead', '19:47 Uhr Weather'] => 'Weather: Storm ahead',
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
      %w[St Storm] => 'Storm: St'
    }.each do |(headline, kicker), expected|
      it "composes #{headline.inspect} with kicker #{kicker.inspect} as #{expected.inspect}" do
        expect(described_class.compose(headline, kicker:)).to eq(expected)
      end
    end

    {
      "Tram line extends\nto the eastern districts" => 'Tram line extends to the eastern districts',
      "  Tram line\t extends  " => 'Tram line extends',
      '9:15 Park planting day' => 'Park planting day',
      '21:00:30 Council approves' => 'Council approves',
      '9:15 PM Council approves' => 'Council approves',
      '9:15pm Council approves' => 'Council approves',
      '9:15 am Bahnhof gesperrt' => 'am Bahnhof gesperrt',
      '9:155 trains cancelled' => '9:155 trains cancelled',
      '12:30 | 10:00 Council approves' => 'Council approves',
      ': Council approves' => 'Council approves',
      'Artikeltyp: Video Museum öffnet wieder' => 'Museum öffnet wieder',
      "Type d'article : Vidéo Le musée rouvre" => 'Le musée rouvre',
      'Tipo de artículo: Audio El museo reabre' => 'El museo reabre',
      'Article type: Live blog Council votes' => 'Council votes',
      'Article type: Council votes' => 'Council votes',
      'Category: Council votes' => 'Council votes',
      'Video shows the new tram line' => 'Video shows the new tram line',
      'Council approves:' => 'Council approves',
      '2:1 win for the home side' => '2:1 win for the home side'
    }.each do |headline, expected|
      it "cleans #{headline.inspect} to #{expected.inspect}" do
        expect(described_class.compose(headline)).to eq(expected)
      end
    end

    it 'returns nil for a blank or noise-only headline even with a kicker', :aggregate_failures do
      expect(described_class.compose(nil, kicker: 'Weather')).to be_nil
      expect(described_class.compose(" \n ", kicker: 'Weather')).to be_nil
      expect(described_class.compose('19:47', kicker: 'Weather')).to be_nil
    end

    it 'is idempotent on its own output' do
      title = described_class.compose('12:30 Storm ahead', kicker: 'Rubrik: Weather :')

      expect(described_class.compose(title)).to eq(title)
    end
  end
end
