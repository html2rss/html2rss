# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Date do
  describe '.earliest' do
    it 'returns the earliest parseable datetime' do
      values = ['2026-03-28T12:00:00Z', 'not-a-date', '2026-01-01T00:00:00Z']
      expect(described_class.earliest(values)).to eq(DateTime.parse('2026-01-01T00:00:00Z'))
    end
  end
end
