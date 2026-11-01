# frozen_string_literal: true

RSpec.describe Html2rss::Test::ItemSample do
  let(:full_article) do
    Html2rss::Article.new(
      title: '  Full Story  ', url: 'https://example.com/full', published_at: '2024-01-02T03:04:05Z',
      description: "<p>Hello   <b>world</b></p>\n<p>again</p>", image: 'https://example.com/i.jpg',
      categories: ['news', ' tech ', 'news']
    )
  end
  let(:bare_article) { Html2rss::Article.new(title: 'Bare') }

  describe '.call' do
    it 'maps every field of a complete article', :aggregate_failures do
      expect(described_class.call([full_article], limit: 3)).to eq(
        [{ title: 'Full Story', url: 'https://example.com/full', published_at: '2024-01-02T03:04:05+00:00',
           description: 'Hello world again', image: 'https://example.com/i.jpg', categories: %w[news tech] }]
      )
    end

    it 'returns nil or empty values for missing fields' do
      expect(described_class.call([bare_article], limit: 3)).to eq(
        [{ title: 'Bare', url: nil, published_at: nil, description: '', image: nil, categories: [] }]
      )
    end

    it 'uses an empty title when the article has none' do
      expect(described_class.call([Html2rss::Article.new(url: 'https://example.com/x')],
                                  limit: 1).first[:title]).to eq('')
    end

    it 'caps the result at the limit', :aggregate_failures do
      articles = [full_article, bare_article, full_article]

      expect(described_class.call(articles, limit: 2).size).to eq(2)
      expect(described_class.call(articles, limit: 0)).to eq([])
    end
  end

  describe '.plain_description' do
    it 'truncates to 200 characters', :aggregate_failures do
      expect(described_class.plain_description("<p>#{'a' * 250}</p>").size).to eq(200)
      expect(described_class.plain_description('a' * 200).size).to eq(200)
    end

    it 'collapses runs of mixed whitespace to single spaces' do
      expect(described_class.plain_description("<p>a  \n\t b</p>\n<p>c</p> d")).to eq('a b c d')
    end

    it 'strips surrounding whitespace before truncating' do
      expect(described_class.plain_description("<p> \n lead</p>\n")).to eq('lead')
    end

    it 'returns an empty string for nil' do
      expect(described_class.plain_description(nil)).to eq('')
    end
  end
end
