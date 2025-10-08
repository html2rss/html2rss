# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Articles::Deduplicator do
  subject(:deduplicated) { described_class.new(articles).call }

  let(:scraper) { Class.new }

  describe '#call' do
    context 'when multiple sources provide overlapping articles' do
      let(:articles) do
        [
          build_article(id: 'a', url: 'https://example.com/a', title: 'Alpha'),
          build_article(id: 'b', url: 'https://example.com/b', title: 'Beta'),
          build_article(id: 'a', url: 'https://example.com/a', title: 'Alpha (selectors)'),
          build_article(id: 'c', url: 'https://example.com/c', title: 'Gamma'),
          build_article(id: 'b', url: 'https://example.com/b', title: 'Beta (auto)')
        ]
      end
      let(:expected_articles) { articles.values_at(0, 1, 3) }

      it 'removes duplicates while preserving order of first occurrences' do
        expect(deduplicated).to eq(expected_articles)
      end

      it 'keeps articles in their original relative order' do
        expect(deduplicated.map(&:id)).to eq(%w[a b c])
      end
    end

    context 'when articles do not expose a guid' do
      let(:rss_article_class) { Html2rss::RssBuilder::Article }
      let(:shared_url) { instance_double(Html2rss::Url, to_s: 'https://example.com/shared') }
      let(:unique_url) { instance_double(Html2rss::Url, to_s: 'https://example.com/unique') }
      let(:shared_fingerprint) { 'https://example.com/shared#!/shared' }
      let(:unique_fingerprint) { 'https://example.com/unique#!/unique' }
      let(:first_article) { instance_double(rss_article_class, guid: nil, id: 'shared', url: shared_url, scraper:) }
      let(:second_article) { instance_double(rss_article_class, guid: nil, id: 'shared', url: shared_url, scraper:) }
      let(:third_article) { instance_double(rss_article_class, guid: nil, id: 'unique', url: unique_url, scraper:) }
      let(:articles) do
        [first_article, second_article, third_article]
      end

      before do
        allow(first_article).to receive(:deduplication_fingerprint).and_return(shared_fingerprint)
        allow(second_article).to receive(:deduplication_fingerprint).and_return(shared_fingerprint)
        allow(third_article).to receive(:deduplication_fingerprint).and_return(unique_fingerprint)
      end

      it 'falls back to the combination of id and URL to deduplicate' do
        expect(deduplicated.map(&:id)).to eq(%w[shared unique])
      end

      it 'delegates fingerprint calculation to the article', :aggregate_failures do
        deduplicated

        expect(first_article).to have_received(:deduplication_fingerprint)
        expect(second_article).to have_received(:deduplication_fingerprint)
        expect(third_article).to have_received(:deduplication_fingerprint)
      end
    end
  end

  def build_article(id:, url:, title:, description: 'Description')
    Html2rss::RssBuilder::Article.new(id:, url:, title:, description:, scraper:)
  end
end
