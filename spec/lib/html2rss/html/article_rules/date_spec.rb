# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Date do
  describe '.earliest' do
    it 'returns the earliest parseable datetime' do
      values = ['2026-03-28T12:00:00Z', 'not-a-date', '2026-01-01T00:00:00Z']
      expect(described_class.earliest(values)).to eq(DateTime.parse('2026-01-01T00:00:00Z'))
    end

    it 'parses date-shaped leftover lines in the channel time zone', :aggregate_failures do
      result = described_class.earliest(
        [], leftover_lines: ['12 March 2024 - News article'], time_zone: 'Europe/Berlin'
      )

      expect(result.to_date).to eq(Date.new(2024, 3, 12))
      expect(result.zone).to eq('+01:00')
    end

    it 'does not parse long teaser lines as dates' do
      teaser = "On 12 March 2024 the company ordered additional dual-fuel vessels for the Asia route #{'word ' * 40}"
      expect(described_class.earliest([], leftover_lines: [teaser])).to be_nil
    end
  end
end
