# frozen_string_literal: true

RSpec.describe Html2rss::LinkDestination::TextClassifier do # rubocop:disable RSpec/SpecFilePathFormat
  describe '.strip_bidi' do
    it 'removes every direction mark and control', :aggregate_failures do
      all = [0x200E, 0x200F, 0x061C, 0x202A, 0x202E, 0x2066, 0x2069].pack('U*')
      expect(described_class.strip_bidi("#{all}a")).to eq('a')
      expect(described_class.strip_bidi("#{[0x202E].pack('U')}b#{[0x2066].pack('U')}")).to eq('b')
    end

    it 'keeps ZWNJ and ZWJ' do
      joined = "a#{[0x200C, 0x200D].pack('U*')}b"
      expect(described_class.strip_bidi(joined)).to eq(joined)
    end

    it 'returns text without marks as the same object' do
      text = +'Video'
      expect(described_class.strip_bidi(text)).to equal(text)
    end
  end
end
