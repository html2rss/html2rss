# frozen_string_literal: true

RSpec.describe Html2rss::WordCount do
  describe '.count' do
    {
      nil => 0, '' => 0, '  –  ' => 0,
      'Tram line extends east' => 4,
      'Straßenbahn: 3 neue Haltestellen' => 4,
      'アクメ 会員の登録情報およそ4万2千件が外部へ' => 5,
      '令和8年11月' => 2,
      '政府' => 1,
      '日銀' => 1,
      '市長は第３２回市民文化祭と記念式典の開会式であいさつした' => 5
    }.each do |text, expected|
      it "counts #{expected} for #{text.inspect}" do
        expect(described_class.count(text)).to eq(expected)
      end
    end

    it 'stops at the ceiling' do
      expect(described_class.count('one two three four five', ceiling: 3)).to eq(3)
    end

    it 'stops at the ceiling a chunk overshoots' do
      expect(described_class.count('日本語のニュース記事です もう一つ', ceiling: 1)).to eq(2)
    end
  end

  describe '.runs' do
    {
      'Platform-launch, notes!' => 3, 'one 42 three' => 3, '会員の登録情報およそ' => 1, '' => 0, nil => 0
    }.each do |text, expected|
      it "counts #{expected} letter/digit runs in #{text.inspect}" do
        expect(described_class.runs(text)).to eq(expected)
      end
    end

    it 'stops at the ceiling', :aggregate_failures do
      expect(described_class.runs('one two three four', ceiling: 2)).to eq(2)
      expect(described_class.runs('one two', ceiling: 3)).to eq(2)
    end
  end

  describe '.at_least?' do
    it 'reads unspaced Japanese by character chunks' do
      expect(described_class.at_least?('アクメ 会員の登録情報およそ4万2千件が外部へ', 3)).to be(true)
    end

    it 'stops counting at the limit' do
      expect(described_class.at_least?('one two three', 2)).to be(true)
    end

    it 'is true for exactly the limit' do
      expect(described_class.at_least?('one two', 2)).to be(true)
    end

    it 'is false below the limit' do
      expect(described_class.at_least?('Weather today', 3)).to be(false)
    end
  end
end
