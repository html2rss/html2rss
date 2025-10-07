# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::ArticlePipeline::Processors::Deduplicator do
  subject(:deduplicated) { described_class.new(articles).call }

  let(:scraper) { Class.new }

  describe '#call' do
    context 'when multiple sources provide overlapping articles' do
      let(:articles) do
        [article_a, article_b, duplicate_article_a, article_c, duplicate_article_b]
      end

      let(:article_a) { build_article(id: 'a', url: 'https://example.com/a', title: 'Alpha') }
      let(:article_b) { build_article(id: 'b', url: 'https://example.com/b', title: 'Beta') }
      let(:article_c) { build_article(id: 'c', url: 'https://example.com/c', title: 'Gamma') }
      let(:duplicate_article_a) { build_article(id: 'a', url: 'https://example.com/a', title: 'Alpha (selectors)') }
      let(:duplicate_article_b) { build_article(id: 'b', url: 'https://example.com/b', title: 'Beta (auto)') }

      it 'removes duplicates while preserving order of first occurrences' do
        expect(deduplicated).to eq([article_a, article_b, article_c])
      end

      it 'keeps articles in their original relative order' do
        expect(deduplicated.map(&:id)).to eq(%w[a b c])
      end
    end

    context 'when articles do not expose a guid' do
      let(:url) { instance_double(Html2rss::Url, to_s: 'https://example.com/shared') }
      let(:articles) do
        [article_without_guid, duplicate_without_guid, unique_article]
      end
      let(:article_without_guid) do
        instance_double('Html2rss::RssBuilder::Article', guid: nil, id: 'shared', url:, scraper:)
      end
      let(:duplicate_without_guid) do
        instance_double('Html2rss::RssBuilder::Article', guid: nil, id: 'shared', url:, scraper:)
      end
      let(:unique_article) do
        instance_double('Html2rss::RssBuilder::Article', guid: nil, id: 'unique', url: instance_double(Html2rss::Url, to_s: 'https://example.com/unique'), scraper:)
      end

      it 'falls back to the combination of id and URL to deduplicate' do
        expect(deduplicated).to eq([article_without_guid, unique_article])
      end
    end
  end

  def build_article(id:, url:, title:, description: 'Description')
    Html2rss::RssBuilder::Article.new(id:, url:, title:, description:, scraper:)
  end
end
