# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Description do
  let(:vocabulary) { Html2rss::Vocabulary[nil] }

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
    it 'reads a digitless line without peeling or matching date shapes', :aggregate_failures do
      allow(described_class).to receive(:date_core).and_call_original

      expect(described_class.date_shaped?('Press releases')).to be(false)
      expect(described_class.date_shaped?(nil)).to be(false)
      expect(described_class).not_to have_received(:date_core)
      expect(described_class.date_shaped?('2024-03-12')).to be(true)
    end

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

    it 'rejects a clock plus teaser after a date separator', :aggregate_failures do
      expect(described_class.date_shaped?('12 March 2024 - 10:00 Team announces a new reactor design'))
        .to be(false)
      expect(described_class.date_shaped?('12 March 2024 | 10:00 Team announces a new reactor design'))
        .to be(false)
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
      expect(described_class.keep?('Press release • 16 juli, 2026', vocabulary:)).to be(false)
    end

    ['Read more', 'Weiterlesen', 'Lire la suite', 'Find out more', 'Meer informatie', 'Más información'].each do |line|
      it "drops the read-more line #{line.inspect}" do
        expect(described_class.keep?(line, vocabulary:)).to be(false)
      end
    end

    it 'keeps a longer read-more sentence' do
      expect(described_class.keep?('Read more about the trial', vocabulary:)).to be(true)
    end

    it 'keeps a teaser that follows a clock, not the whole line as date chrome', :aggregate_failures do
      expect(described_class.keep?('12 March 2024 - 10:00 Team announces a new reactor design',
                                   vocabulary:)).to be(true)
      expect(described_class.keep?('12 March 2024 | 10:00 Team announces a new reactor design',
                                   vocabulary:)).to be(true)
    end

    it 'still drops a Nokia-shaped pipe clock line as description chrome' do
      expect(described_class.keep?('August 06 , 2026 | 13:00 PM Europe/Amsterdam', vocabulary:)).to be(false)
    end

    it 'drops the Japanese type chips 独自 and 写真 on a Japanese or unlabeled page, not on a Chinese one',
       :aggregate_failures do
      %w[独自 写真].product([nil, :ja, :en]).each do |chip, lang|
        expect(described_class.keep?(chip, vocabulary: Html2rss::Vocabulary[lang])).to be(false), "#{chip} #{lang}"
      end
      %w[独自 写真].each { expect(described_class.keep?(_1, vocabulary: Html2rss::Vocabulary[:zh])).to be(true), _1 }
      expect(described_class.keep?('速報', vocabulary: Html2rss::Vocabulary[:zh])).to be(false)
    end

    it 'peels a 独自 or 写真 chip beside a date on every page, in both orders and with every separator',
       :aggregate_failures do
      %w[独自 写真].product([' - ', ' | ', ' • ']).flat_map { |w, sep| ["2024-03-12#{sep}#{w}", "#{w}#{sep}2024-03-12"] }
               .each do |line|
        expect([described_class.date_core(line), described_class.date_shaped?(line)]).to eq(['2024-03-12', true]), line
        expect(described_class.keep?(line, vocabulary: Html2rss::Vocabulary[:zh])).to be(false), line
      end
    end

    it 'sets published_at from such a chip on a Chinese page, and leaves it out of the description',
       :aggregate_failures do
      zh = Html2rss::Vocabulary[:zh]
      line = '独自 | 2026-11-10'

      expect(Html2rss::Html::ArticleRules::Date.earliest([], leftover_lines: [line], time_zone: 'UTC'))
        .to eq(DateTime.parse('2026-11-10T00:00:00Z'))
      expect(described_class.from_lines([line, 'Kept dek'], vocabulary: zh)).to eq('Kept dek')
    end
  end
end
