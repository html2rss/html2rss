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
      subject(:result) { described_class.call(articles) }

      let(:articles) do
        [
          Html2rss::AutoSource::Article.new(url:, id: 1,
                                            title: 'Title 1',
                                            description: 'Longer Description 1 wins',
                                            generated_by: RSpec),
          Html2rss::AutoSource::Article.new(url:, id: 2,
                                            title: 'Title wins',
                                            description: 'Description 2',
                                            generated_by: RSpec),
          Html2rss::AutoSource::Article.new(url:, id: 3,
                                            title: 'Longer Title 3 wins',
                                            description: 'Description 3',
                                            generated_by: RSpec)
        ]
      end

      it 'keeps the longest attributes of Html2rss::AutoSource::Articles with the same URL', :aggregate_failures do
        expect(result.size).to eq(1)
        expect(result[0].description).to eq('Longer Description 1 wins')
        expect(result[0].title).to eq('Longer Title 3 wins')
        expect(result[0].url).to eq(url)
      end

      it 'keeps the kept attributes' do
        expect(result[0].generated_by).to eq([RSpec, RSpec, RSpec])
      end
    end
  end
end
