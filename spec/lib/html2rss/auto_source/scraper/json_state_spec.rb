# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonState do
  let(:base_url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }

  def load_fixture(name)
    file = File.join(__dir__, '../../../..', 'fixtures/auto_source/json_state', name)
    File.read(file)
  end

  describe '.articles?' do
    it 'detects Next.js JSON state' do
      parsed_body = Nokogiri::HTML(load_fixture('next.html'))

      expect(described_class.articles?(parsed_body)).to be(true)
    end

    it 'detects Nuxt JSON state' do
      parsed_body = Nokogiri::HTML(load_fixture('nuxt.html'))

      expect(described_class.articles?(parsed_body)).to be(true)
    end

    it 'detects custom window state blobs' do
      parsed_body = Nokogiri::HTML(load_fixture('state.html'))

      expect(described_class.articles?(parsed_body)).to be(true)
    end

    it 'returns false when no JSON state is present' do
      parsed_body = Nokogiri::HTML('<html><body><script>console.log("hello")</script></body></html>')

      expect(described_class.articles?(parsed_body)).to be(false)
    end
  end

  describe '#each' do
    subject(:articles) { described_class.new(parsed_body, url: base_url).each.to_a }

    context 'with Next.js data' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('next.html')) }

      it 'normalises the article data' do
        expect(articles.size).to eq(1)

        article = articles.first
        expect(article[:title]).to eq('Next.js powers the latest headlines')
        expect(article[:description]).to eq('A summary sourced from Next.js JSON state.')
        expect(article[:url]).to eq(Html2rss::Url.from_relative('/next/headline', base_url))
        expect(article[:image]).to eq(Html2rss::Url.from_relative('https://cdn.example.com/images/next/headline.jpg', base_url))
        expect(article[:published_at]).to eq('2024-04-01T12:00:00Z')
        expect(article[:categories]).to eq(%w[nextjs spa])
        expect(article[:id]).to eq('next-article-1')
      end
    end

    context 'with Nuxt data' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('nuxt.html')) }

      it 'extracts relative URLs and nested categories' do
        expect(articles.size).to eq(1)

        article = articles.first
        expect(article[:title]).to eq('Nuxt article arrives')
        expect(article[:description]).to eq('Nuxt.js embeds article data into a global.')
        expect(article[:url]).to eq(Html2rss::Url.from_relative('/nuxt/article', base_url))
        expect(article[:image]).to eq(Html2rss::Url.from_relative('/images/nuxt/article.jpg', base_url))
        expect(article[:published_at]).to eq('2024-04-02T10:00:00Z')
        expect(article[:categories]).to eq(%w[nuxt spa])
        expect(article[:id]).to eq('https://example.com/nuxt/article')
      end
    end

    context 'with custom window state' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('state.html')) }

      it 'handles bespoke globals' do
        expect(articles.size).to eq(1)

        article = articles.first
        expect(article[:title]).to eq('Window state update')
        expect(article[:description]).to eq('Content embedded in a custom window.STATE blob.')
        expect(article[:url]).to eq(Html2rss::Url.from_relative('/state/update', base_url))
        expect(article[:image]).to eq(Html2rss::Url.from_relative('/images/state/update.png', base_url))
        expect(article[:published_at]).to eq('2024-04-03T08:30:00Z')
        expect(article[:categories]).to eq(%w[updates custom])
        expect(article[:id]).to eq('state-post-42')
      end
    end
  end
end
