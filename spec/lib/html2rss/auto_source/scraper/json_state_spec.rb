# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonState do
  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }

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

    it 'detects additional framework globals' do
      parsed_body = Nokogiri::HTML(load_fixture('redux.html'))

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
            image: Html2rss::Url.from_absolute('https://cdn.example.com/images/next/headline.jpg'),
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
        expect(articles).to contain_exactly(a_hash_including(
                                              title: 'Nested article',
                                              url: Html2rss::Url.from_relative('/nested/article',
                                                                               base_url)
                                            ))
      end
    end

    context 'with Redux preloaded state' do
      let(:parsed_body) { Nokogiri::HTML(load_fixture('redux.html')) }

      it 'extracts article-like hashes from additional framework globals' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Redux article',
            description: 'State embedded via a Redux convention.',
            url: Html2rss::Url.from_relative('/redux/article', base_url),
            image: Html2rss::Url.from_relative('/images/redux/article.jpg', base_url),
            published_at: '2024-04-04T09:00:00Z',
            categories: %w[redux spa],
            id: 'redux-article-1'
          )
        )
      end
    end

    context 'with nested attributes and data nodes' do
      let(:expected_article) do
        a_hash_including(
          title: 'Nested data article',
          url: Html2rss::Url.from_relative('/nested/data', base_url)
        )
      end

      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><body><script type="application/json">' \
          '[{"data":{"attributes":{"title":"Nested data article","url":"/nested/data"}}}]' \
          '</script></body></html>'
        )
      end

      it 'extracts article values through symbolized nested keys' do
        expect(articles).to contain_exactly(expected_article)
      end
    end
  end

  describe '.discover_articles' do
    subject(:articles) do
      found = []
      described_class.discover_articles(document, base_url:) { |article| found << article }
      found
    end

    context 'when walking nested hashes for shared XHR reuse' do
      let(:document) do
        {
          payload: {
            items: [
              { title: 'Shared walk', url: '/shared' }
            ]
          }
        }
      end

      it 'yields the nested article', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Shared walk',
            url: Html2rss::Url.from_relative('/shared', base_url)
          )
        )
      end
    end

    context 'with listing fields name, link, description, categories, and icon' do
      let(:document) do
        [
          {
            name: 'Long Enough App Name',
            link: 'https://apps.apple.com/app/id1',
            description: 'A short pitch.',
            categories: %w[games productivity],
            icon: 'https://cdn.example.com/icon.png'
          }
        ]
      end

      it 'normalises those fields into an article hash' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Long Enough App Name',
            description: 'A short pitch.',
            url: Html2rss::Url.from_absolute('https://apps.apple.com/app/id1'),
            categories: %w[games productivity],
            image: Html2rss::Url.from_absolute('https://cdn.example.com/icon.png')
          )
        )
      end
    end

    context 'with Drupal path.alias under attributes' do
      let(:document) do
        [{ attributes: { title: 'Drupal node', path: { alias: '/nodes/1', langcode: 'en' } } }]
      end

      it 'resolves the alias as the article URL' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Drupal node',
            url: Html2rss::Url.from_relative('/nodes/1', base_url)
          )
        )
      end
    end

    context 'with links.self.href' do
      let(:document) do
        [
          {
            title: 'JSON:API resource',
            links: { self: { href: 'https://example.com/jsonapi/node/1' } }
          }
        ]
      end

      it 'resolves self.href as the article URL' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'JSON:API resource',
            url: Html2rss::Url.from_absolute('https://example.com/jsonapi/node/1')
          )
        )
      end
    end

    context 'with array-form links containing href' do
      let(:document) do
        [
          {
            title: 'HAL-style links',
            links: [
              { rel: 'related', href: 'https://example.com/related' },
              { rel: 'self', href: 'https://example.com/hal/1' }
            ],
            description: 'URL only in links array entries.'
          }
        ]
      end

      it 'resolves the first href from the links array' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'HAL-style links',
            description: 'URL only in links array entries.',
            url: Html2rss::Url.from_absolute('https://example.com/related')
          )
        )
      end
    end

    context 'with an unparseable article URL' do
      let(:document) { [{ title: 'Broken URL', url: ':::', description: 'Skipped' }] }

      before { allow(Html2rss::Log).to receive(:debug) }

      it 'logs a single-string debug message and yields no article', :aggregate_failures do
        expect(articles.compact).to be_empty
        expect(Html2rss::Log).to have_received(:debug).with(
          a_string_including('JsonState: invalid URL encountered', 'url=:::')
        )
      end
    end

    context 'with published_on after the closed date-key list misses' do
      let(:document) { [{ title: 'Dated item', url: '/dated', published_on: '2024-06-15' }] }

      it 'keeps published_on as published_at' do
        expect(articles).to contain_exactly(
          a_hash_including(title: 'Dated item', published_at: '2024-06-15')
        )
      end
    end

    context 'with saleStartDate' do
      let(:document) { [{ title: 'Sale item', url: '/sale', saleStartDate: '2024-07-01' }] }

      it 'does not treat saleStartDate as published_at', :aggregate_failures do
        expect(articles).to contain_exactly(a_hash_including(title: 'Sale item'))
        expect(articles.first).not_to include(:published_at)
      end
    end

    context 'with a JSON:API type and no category keys' do
      let(:document) do
        [{ title: 'Typed node', url: '/typed', type: 'node--event', description: 'Body' }]
      end

      it 'does not treat type as a category', :aggregate_failures do
        expect(articles).to contain_exactly(a_hash_including(title: 'Typed node'))
        expect(articles.first).not_to include(:categories)
      end
    end

    context 'with link and image src' do
      let(:document) do
        [
          {
            title: 'Image card',
            link: '/article',
            src: 'https://cdn.example.com/hero.jpg'
          }
        ]
      end

      it 'does not use src as the article URL' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Image card',
            url: Html2rss::Url.from_relative('/article', base_url),
            image: Html2rss::Url.from_absolute('https://cdn.example.com/hero.jpg')
          )
        )
      end
    end

    context 'with WordPress-style rendered title and excerpt' do
      let(:document) do
        [
          {
            title: { rendered: 'How to build a feed' },
            excerpt: { rendered: '<p>A short excerpt.</p>' },
            link: '/feed-reader'
          }
        ]
      end

      it 'unwraps rendered scalars without publishing Hash#to_s', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'How to build a feed',
            description: '<p>A short excerpt.</p>',
            url: Html2rss::Url.from_relative('/feed-reader', base_url)
          )
        )
        expect(articles.first[:title]).not_to include('rendered')
      end
    end

    context 'with a title hash that has no scalar wrapper keys' do
      let(:document) do
        [{ title: { locale: 'en', format: 'plain' }, url: '/no-scalar' }]
      end

      it 'yields nothing when title and description cannot be unwrapped' do
        expect(articles.compact).to be_empty
      end
    end
  end
end
