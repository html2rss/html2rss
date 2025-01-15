# frozen_string_literal: true

require 'addressable'

RSpec.describe Html2rss::AutoSource::Reducer do
  let(:url) { Addressable::URI.parse('http://example.com') }

  describe '.call' do
    let(:articles) { [Html2rss::RssBuilder::Article.new(url: true)] }

    it 'returns an array of Html2rss::RssBuilder::Articles' do
      result = described_class.call(articles)
      expect(result).to be_an(Array)
    end

    describe 'reducing articles' do
      subject(:result) { described_class.call(articles) }

      let(:articles) do
        [
          Html2rss::RssBuilder::Article.new(url:, id: 1,
                                            title: 'Title 1',
                                            description: 'Longer Description 1 wins',
                                            scraper: RSpec),
          Html2rss::RssBuilder::Article.new(url:, id: 2,
                                            title: 'Title wins',
                                            description: 'Description 2',
                                            scraper: RSpec),
          Html2rss::RssBuilder::Article.new(url:, id: 3,
                                            title: 'Longer Title 3 wins',
                                            description: 'Description 3',
                                            scraper: RSpec)
        ]
      end

      it 'keeps the longest attributes of Html2rss::RssBuilder::Articles with the same URL', :aggregate_failures do
        expect(result.size).to eq(1)
        expect(result[0].description).to eq('Longer Description 1 wins')
        expect(result[0].title).to eq('Longer Title 3 wins')
        expect(result[0].url).to eq(url)
      end

      it 'keeps the kept attributes' do
        expect(result[0].scraper).to eq([RSpec, RSpec, RSpec])
      end
    end
  end
end
