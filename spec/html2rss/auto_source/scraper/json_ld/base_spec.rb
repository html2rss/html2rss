# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonLd::Base do
  describe '.to_article(article)' do
    subject(:to_article) { described_class.to_article(article, url: nil) }

    context 'with unparsable date' do
      let(:article) do
        { datePublished: 'unparsable_date_string' }
      end

      it 'returns published_at: nil' do
        expect(to_article).to include(published_at: nil)
      end
    end
  end
end
