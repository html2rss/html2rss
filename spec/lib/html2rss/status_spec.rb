# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Status do
  describe '.build' do
    let(:articles) do
      [
        Html2rss::Article.new(id: '1', title: 'A', url: 'https://example.com/a', scraper: Html2rss::Selectors),
        Html2rss::Article.new(id: '2', title: 'B', url: 'https://example.com/b', scraper: Html2rss::Selectors),
        Html2rss::Article.new(id: '3', title: 'C', url: 'https://example.com/c',
                              scraper: Html2rss::AutoSource::Scraper::Html)
      ]
    end

    it 'records version, scraper tallies, and dedup_dropped', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      status = described_class.build(articles:, dedup_dropped: 2)

      expect(status.version).to eq(Html2rss::VERSION)
      expect(status.scraper_tallies).to eq('Selectors' => 2, 'AutoSource::Html' => 1)
      expect(status.dedup_dropped).to eq(2)
      expect(status.selected_strategy).to be_nil
      expect(status.attempt_count).to eq(0)
    end

    # rubocop:disable RSpec/ExampleLength -- auto summary + to_h + generator non-bloat
    it 'accepts auto strategy summary without putting it in the generator string', :aggregate_failures do
      status = described_class.build(
        articles:,
        dedup_dropped: 0,
        selected_strategy: :botasaurus,
        attempt_count: 2
      )

      expect(status.selected_strategy).to eq(:botasaurus)
      expect(status.attempt_count).to eq(2)
      expect(status.to_h).to include(selected_strategy: :botasaurus, attempt_count: 2)
      expect(status.to_generator_comment).not_to include('botasaurus')
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '#to_generator_comment' do
    subject(:comment) do
      described_class.new(
        version: '9.9.9',
        scraper_tallies: { 'Selectors' => 2, 'AutoSource::Html' => 1 },
        dedup_dropped: 0
      ).to_generator_comment
    end

    it 'formats the RSS generator / JSON Feed user_comment string' do
      expect(comment).to eq('html2rss V. 9.9.9 (scrapers: Selectors (2), AutoSource::Html (1))')
    end
  end
end
