# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Description do
  describe '.date_core' do
    it 'strips a known type-chip suffix after a dash', :aggregate_failures do
      expect(described_class.date_core('12 March 2024 - News article')).to eq('12 March 2024')
      expect(described_class.date_core('12 March 2024 – Press release')).to eq('12 March 2024')
      expect(described_class.date_core('12 March 2024 — News')).to eq('12 March 2024')
    end

    it 'leaves lines without a type-chip suffix unchanged' do
      expect(described_class.date_core('12 March 2024 - something else'))
        .to eq('12 March 2024 - something else')
    end
  end

  describe '.date_shaped?' do
    it 'accepts whole-line date shapes', :aggregate_failures do
      expect(described_class.date_shaped?('2024-03-12')).to be(true)
      expect(described_class.date_shaped?('2024-03-12T12:00:00Z')).to be(true)
      expect(described_class.date_shaped?('12/03/2024')).to be(true)
      expect(described_class.date_shaped?('12 March 2024')).to be(true)
      expect(described_class.date_shaped?('March 12, 2024')).to be(true)
    end

    it 'accepts a date with a type-chip suffix' do
      expect(described_class.date_shaped?('12 March 2024 - News article')).to be(true)
    end

    it 'normalizes unicode space before matching' do
      expect(described_class.date_shaped?("12\u00A0March\u00A02024")).to be(true)
    end

    it 'rejects teasers and space-padded junk', :aggregate_failures do
      expect(described_class.date_shaped?('On 12 March 2024 the company ordered vessels')).to be(false)
      expect(described_class.date_shaped?("a#{' ' * 10_000}")).to be(false)
      expect(described_class.date_shaped?("a - #{'  ' * 5_000}")).to be(false)
    end

    it 'accepts a Nokia-shaped pipe date with spaced comma and clock zone' do
      expect(described_class.date_shaped?('August 06 , 2026 | 13:00 PM Europe/Amsterdam')).to be(true)
    end

    it 'accepts a Telenor-shaped leading type-chip with juli' do
      expect(described_class.date_shaped?('Press release • 16 juli, 2026')).to be(true)
    end
  end

  describe '.date_core Nokia/Telenor fragments' do
    it 'keeps the calendar day from a pipe clock line' do
      expect(described_class.date_core('August 06 , 2026 | 13:00 PM Europe/Amsterdam'))
        .to match(/August 06\s*,?\s*2026/)
    end
  end

  describe '.keep?' do
    it 'drops a Telenor-shaped type-chip date line' do
      expect(described_class.keep?('Press release • 16 juli, 2026')).to be(false)
    end

    it 'keeps a longer read-more sentence' do
      expect(described_class.keep?('Read more about the trial')).to be(true)
    end
  end
end
