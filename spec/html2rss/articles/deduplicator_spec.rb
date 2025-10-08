# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Articles::Deduplicator do
  subject(:deduplicated) { described_class.new(articles).call }

  let(:scraper) { Class.new }

  describe '#initialize' do
    it 'requires articles' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, 'articles must be provided')
    end
  end

  describe '#call' do
    context 'when multiple sources provide overlapping articles' do
      let(:articles) do
        defaults = { description: 'Description', scraper: }
        article_args = [
          { id: 'a', url: 'https://example.com/a', title: 'Alpha' },
          { id: 'b', url: 'https://example.com/b', title: 'Beta' },
          { id: 'a', url: 'https://example.com/a', title: 'Alpha (selectors)' },
          { id: 'c', url: 'https://example.com/c', title: 'Gamma' },
          { id: 'b', url: 'https://example.com/b', title: 'Beta (auto)' }
        ]

        article_args.map do |attrs|
          Html2rss::RssBuilder::Article.new(**defaults, **attrs)
        end
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
      let(:articles) do
        shared_fingerprint = 'https://example.com/shared#!/shared'
        unique_fingerprint = 'https://example.com/unique#!/unique'

        shared_url = instance_double(Html2rss::Url, to_s: 'https://example.com/shared')
        unique_url = instance_double(Html2rss::Url, to_s: 'https://example.com/unique')

        first_article = instance_double(
          Html2rss::RssBuilder::Article,
          guid: nil,
          id: 'shared',
          url: shared_url,
          scraper:
        )
        second_article = instance_double(
          Html2rss::RssBuilder::Article,
          guid: nil,
          id: 'shared',
          url: shared_url,
          scraper:
        )
        third_article = instance_double(
          Html2rss::RssBuilder::Article,
          guid: nil,
          id: 'unique',
          url: unique_url,
          scraper:
        )

        allow(first_article).to receive(:deduplication_fingerprint).and_return(shared_fingerprint)
        allow(second_article).to receive(:deduplication_fingerprint).and_return(shared_fingerprint)
        allow(third_article).to receive(:deduplication_fingerprint).and_return(unique_fingerprint)

        [first_article, second_article, third_article]
      end

      it 'falls back to the combination of id and URL to deduplicate' do
        expect(deduplicated.map(&:id)).to eq(%w[shared unique])
      end

      it 'delegates fingerprint calculation to the article', :aggregate_failures do
        deduplicated

        expect(articles[0]).to have_received(:deduplication_fingerprint)
        expect(articles[1]).to have_received(:deduplication_fingerprint)
        expect(articles[2]).to have_received(:deduplication_fingerprint)
      end
    end
  end
end
