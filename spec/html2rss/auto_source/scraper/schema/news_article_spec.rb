# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::NewsArticle do
  it { expect(described_class).to be < Html2rss::AutoSource::Scraper::Schema::Base }

  describe '#call' do
    subject(:article_hash) { described_class.new({}, url: '').call }

    it 'returns the article hash' do
      expect(article_hash).to include(
        article_body: nil
      )
    end
  end
end
