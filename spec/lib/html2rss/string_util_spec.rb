# frozen_string_literal: true

RSpec.describe Html2rss::StringUtil do
  describe '.blank?' do
    it 'is true for empty, whitespace-only and non-String values', :aggregate_failures do
      ['', " \n\t", nil, 1, :a, ['a'], { a: 1 }].each { |value| expect(described_class.blank?(value)).to be(true) }
    end

    it 'is false for a String with content', :aggregate_failures do
      expect(described_class.blank?('a')).to be(false)
      expect(described_class.blank?(Class.new(String).new('a'))).to be(false)
      expect(described_class.blank?(' a ')).to be(false)
    end

    it 'treats whitespace-only as present with strip: false', :aggregate_failures do
      expect(described_class.blank?(' ', strip: false)).to be(false)
      expect(described_class.blank?('', strip: false)).to be(true)
      expect(described_class.blank?(nil, strip: false)).to be(true)
    end
  end

  describe '.present?' do
    it 'negates blank? for both variants', :aggregate_failures do
      expect(described_class.present?('a')).to be(true)
      expect(described_class.present?(' ')).to be(false)
      expect(described_class.present?(' ', strip: false)).to be(true)
      expect(described_class.present?(1, strip: false)).to be(false)
    end
  end

  describe '.presence' do
    it 'returns the String unchanged (not stripped) when present', :aggregate_failures do
      expect(described_class.presence(' a ')).to eq(' a ')
      expect(described_class.presence(' ', strip: false)).to eq(' ')
    end

    it 'returns nil when blank or not a String', :aggregate_failures do
      [nil, '', ' ', 12, ['a']].each { |value| expect(described_class.presence(value)).to be_nil }
      expect(described_class.presence('', strip: false)).to be_nil
    end
  end
end
