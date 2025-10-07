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

      expect(described_class).to be_articles(parsed_body)
    end

    it 'detects Nuxt JSON state' do
      parsed_body = Nokogiri::HTML(load_fixture('nuxt.html'))

      expect(described_class).to be_articles(parsed_body)
    end

    it 'detects custom window state blobs' do
      parsed_body = Nokogiri::HTML(load_fixture('state.html'))

      expect(described_class).to be_articles(parsed_body)
    end

    it 'detects arrays containing nested article arrays' do
      parsed_body = Nokogiri::HTML(load_fixture('nested_array.html'))

      expect(described_class).to be_articles(parsed_body)
    end

    it 'returns false when no JSON state is present' do
      parsed_body = Nokogiri::HTML('<html><body><script>console.log("hello")</script></body></html>')

      expect(described_class).not_to be_articles(parsed_body)
    end
  end

  describe '#each' do
    subject(:articles) { described_class.new(parsed_body, url: base_url).each.to_a }

    context 'with Next.js data' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('next.html')) }

      it 'normalises the article data' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Next.js powers the latest headlines',
            description: 'A summary sourced from Next.js JSON state.',
            url: Html2rss::Url.from_relative('/next/headline', base_url),
            image: Html2rss::Url.from_relative('https://cdn.example.com/images/next/headline.jpg', base_url),
            published_at: '2024-04-01T12:00:00Z',
            categories: %w[nextjs spa],
            id: 'next-article-1'
          )
        )
      end
    end

    context 'with Nuxt data' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('nuxt.html')) }

      it 'extracts relative URLs and nested categories' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Nuxt article arrives',
            description: 'Nuxt.js embeds article data into a global.',
            url: Html2rss::Url.from_relative('/nuxt/article', base_url),
            image: Html2rss::Url.from_relative('/images/nuxt/article.jpg', base_url),
            published_at: '2024-04-02T10:00:00Z',
            categories: %w[nuxt spa],
            id: 'https://example.com/nuxt/article'
          )
        )
      end
    end

    context 'with custom window state' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('state.html')) }

      it 'handles bespoke globals' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Window state update',
            description: 'Content embedded in a custom window.STATE blob.',
            url: Html2rss::Url.from_relative('/state/update', base_url),
            image: Html2rss::Url.from_relative('/images/state/update.png', base_url),
            published_at: '2024-04-03T08:30:00Z',
            categories: %w[updates custom],
            id: 'state-post-42'
          )
        )
      end
    end

    context 'with nested array data' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('nested_array.html')) }

      it 'finds articles nested inside array entries' do
        expect(articles).to contain_exactly(a_hash_including(title: 'Nested article',
                                                             url: Html2rss::Url.from_relative(
                                                               '/nested/article', base_url
                                                             )))
      end
    end
  end
end
