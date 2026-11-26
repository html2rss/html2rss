# frozen_string_literal: true

RSpec.describe Html2rss::StringUtil do
  describe '.blank?' do
    it 'is true for empty, whitespace-only and non-String values', :aggregate_failures do
      ['', " \n\t", nil, 1, :a, ['a'], { a: 1 }].each { |value| expect(described_class.blank?(value)).to be(true) }
    end

    it 'is false for a String with content', :aggregate_failures do
      expect(described_class.blank?('a')).to be(false)
      expect(described_class.blank?(' a ')).to be(false)
      expect(described_class.blank?(Class.new(String).new('a'))).to be(false)
    end
  end

  describe '.present?' do
    it 'negates blank?', :aggregate_failures do
      expect(described_class.present?('a')).to be(true)
      expect(described_class.present?(' ')).to be(false)
      expect(described_class.present?(1)).to be(false)
    end
  end

  describe '.presence' do
    it 'returns the String unchanged (not stripped) when present' do
      expect(described_class.presence(' a ')).to eq(' a ')
    end

    it 'returns nil when blank or not a String', :aggregate_failures do
      [nil, '', ' ', 12, ['a']].each { |value| expect(described_class.presence(value)).to be_nil }
    end
  end

  describe '.strip_bidi' do
    it 'strips every direction mark and control, but keeps ZWNJ and ZWJ', :aggregate_failures do
      all = [0x200E, 0x200F, 0x061C, 0x202A, 0x202E, 0x2066, 0x2069].pack('U*')
      joined = "a#{[0x200C, 0x200D].pack('U*')}b"
      expect(described_class.strip_bidi("#{all}a")).to eq('a')
      expect(described_class.strip_bidi(joined)).to eq(joined)
    end

    it 'returns text without marks as the same object' do
      text = +'Video'
      expect(described_class.strip_bidi(text)).to equal(text)
    end
  end
end
