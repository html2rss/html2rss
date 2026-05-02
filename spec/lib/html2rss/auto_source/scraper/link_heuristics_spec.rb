# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::LinkHeuristics do
  subject(:heuristics) { described_class.new('https://example.com/articles/') }

  describe '#destination_facts' do
    it 'returns nil when URL normalization rejects a malformed href' do
      expect(heuristics.destination_facts('http://example .com')).to be_nil
    end
  end
end
