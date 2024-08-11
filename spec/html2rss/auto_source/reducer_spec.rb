# frozen_string_literal: true

require 'addressable'

RSpec.describe Html2rss::AutoSource::Reducer do
  let(:url) { Addressable::URI.parse('http://example.com') }

  describe '.call' do
    let(:articles) { [Html2rss::AutoSource::Article.new(url: true)] }

    it 'returns an array of Html2rss::AutoSource::Articles' do
      result = described_class.call(articles)
      expect(result).to be_an(Array)
    end

    describe 'reducing articles' do
      let(:articles) do
        [
          Html2rss::AutoSource::Article.new(url:, id: 1,
                                            title: 'Title 1',
                                            description: 'Longer Description 1 wins'),
          Html2rss::AutoSource::Article.new(url:, id: 2,
                                            title: 'Title wins',
                                            description: 'Description 2'),
          Html2rss::AutoSource::Article.new(url:, id: 3,
                                            title: 'Longer Title 3 wins',
                                            description: 'Description 3')
        ]
      end

      it 'keeps the longest attributes of Html2rss::AutoSource::Articles with the same URL', :aggregate_failures do
        result = described_class.call(articles)

        expect(result.size).to eq(1)
        expect(result[0].description).to eq('Longer Description 1 wins')
        expect(result[0].title).to eq('Longer Title 3 wins')
        expect(result[0].url).to eq(url)
      end
    end

    describe 'filtering out invalid articles' do
      let(:articles) do
        [
          Html2rss::AutoSource::Article.new(url: 'a', id: 1, title: 'Foobar'),
          Html2rss::AutoSource::Article.new(url: 'b', id: 2, title: nil),
          Html2rss::AutoSource::Article.new(url: 'c', id: 3, title: 'Foobar')
        ]
      end

      it 'filters out invalid Html2rss::AutoSource::Articles', :aggregate_failures do
        result = described_class.call(articles)

        expect(result.size).to eq(2)
        expect(result[0].valid?).to be true
        expect(result[1].valid?).to be true
      end
    end
  end
end
