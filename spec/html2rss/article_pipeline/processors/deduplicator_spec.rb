# frozen_string_literal: true

RSpec.describe Html2rss::ArticlePipeline::Processors::Deduplicator do
  subject(:processor) { described_class.new }

  describe '#call' do
    let(:articles) { [first_article, duplicate_article, without_key] }

    let(:first_url) { instance_double(Html2rss::Url, to_s: 'https://example.com/first') }

    let(:first_article) do
      instance_double(Html2rss::RssBuilder::Article, url: first_url, id: nil, title: 'First')
    end

    let(:duplicate_article) do
      instance_double(Html2rss::RssBuilder::Article, url: first_url, id: nil, title: 'First copy')
    end

    let(:without_key) do
      instance_double(Html2rss::RssBuilder::Article, url: nil, id: nil, title: nil)
    end

    it 'removes subsequent articles with an existing deduplication key' do
      expect(processor.call(articles)).to eq([first_article, without_key])
    end

    it 'preserves the order of unique articles' do
      result = processor.call([duplicate_article, first_article, without_key])

      expect(result).to eq([duplicate_article, without_key])
    end
  end
end
