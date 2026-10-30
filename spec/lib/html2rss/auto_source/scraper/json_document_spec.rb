# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonDocument do
  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }

  describe '.articles?' do
    it 'is never detectable from HTML alone' do
      expect(described_class.articles?(Nokogiri::HTML('<html></html>'))).to be(false)
    end
  end

  describe '.options_key' do
    it 'uses the json_document config key' do
      expect(described_class.options_key).to eq(:json_document)
    end
  end

  describe '.request_slots' do
    it 'makes no additional HTTP requests' do
      expect(described_class.request_slots).to eq(0)
    end
  end

  describe '#extractable?' do
    it 'is true for a Hash body' do
      expect(described_class.new({ status: 'ok' }, url: base_url)).to be_extractable
    end

    it 'is true for an Array body' do
      expect(described_class.new([], url: base_url)).to be_extractable
    end

    it 'accepts Hash and Array subclasses', :aggregate_failures do
      expect(described_class.new(Class.new(Hash).new, url: base_url)).to be_extractable
      expect(described_class.new(Class.new(Array).new, url: base_url)).to be_extractable
    end

    it 'is false for a Nokogiri document' do
      scraper = described_class.new(Nokogiri::HTML('<html></html>'), url: base_url)

      expect(scraper).not_to be_extractable
    end
  end

  describe '#each' do
    subject(:articles) { described_class.new(parsed_body, url: base_url).each.to_a }

    context 'with a JSON Feed 1.1 document' do
      let(:parsed_body) do
        {
          version: 'https://jsonfeed.org/version/1.1',
          title: 'Example Feed',
          items: [
            {
              id: 'https://example.com/posts/1',
              url: 'https://example.com/posts/1',
              title: 'First post',
              content_text: 'Plain body',
              date_published: '2024-06-01T12:00:00Z',
              image: 'https://cdn.example.com/1.jpg',
              tags: %w[news example]
            },
            {
              id: 'relative-id-only',
              title: 'No absolute URL',
              content_html: '<p>Skipped</p>'
            },
            {
              id: 'https://example.com/posts/2',
              title: 'Id as URL',
              content_html: '<p>HTML body</p>'
            }
          ]
        }
      end

      it 'maps JSON Feed fields and skips items without a URL', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'First post',
            description: 'Plain body',
            url: Html2rss::Url.from_absolute('https://example.com/posts/1'),
            image: Html2rss::Url.from_absolute('https://cdn.example.com/1.jpg'),
            published_at: '2024-06-01T12:00:00Z',
            categories: %w[news example],
            id: 'https://example.com/posts/1'
          ),
          a_hash_including(
            title: 'Id as URL',
            description: '<p>HTML body</p>',
            url: Html2rss::Url.from_absolute('https://example.com/posts/2'),
            id: 'https://example.com/posts/2'
          )
        )
      end
    end

    context 'with a JSON Feed 1.0 document' do
      let(:parsed_body) do
        {
          version: 'https://jsonfeed.org/version/1',
          title: 'Legacy Feed',
          items: [
            {
              id: 'https://example.com/legacy/1',
              url: 'https://example.com/legacy/1',
              title: 'Legacy post',
              content_text: 'Body'
            }
          ]
        }
      end

      it 'maps items via the JSON Feed path' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Legacy post',
            url: Html2rss::Url.from_absolute('https://example.com/legacy/1')
          )
        )
      end
    end

    context 'with an adversarial JSON Feed version substring' do
      let(:parsed_body) do
        {
          version: 'https://evil.example/jsonfeed.org/version/1.1',
          title: 'Not a feed',
          items: [
            {
              id: 'https://example.com/posts/1',
              title: 'Should walk via JsonState',
              url: 'https://example.com/posts/1',
              content_text: 'Only JSON Feed maps content_text'
            }
          ]
        }
      end

      it 'does not unlock JSON Feed mapping from a substring host', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Should walk via JsonState',
            url: Html2rss::Url.from_absolute('https://example.com/posts/1')
          )
        )
        expect(articles.first).not_to include(:description)
      end
    end

    context 'with a lookalike JSON Feed version host' do
      let(:parsed_body) do
        {
          version: 'https://jsonfeed.org.evil.example/version/1.1',
          items: [
            { title: 'Lookalike host', url: 'https://example.com/lookalike', description: 'Ok' }
          ]
        }
      end

      it 'still discovers the item via JsonState without JSON Feed recognition' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Lookalike host',
            url: Html2rss::Url.from_absolute('https://example.com/lookalike')
          )
        )
      end
    end

    context 'with array-form links on a JSON document listing' do
      let(:parsed_body) do
        [
          {
            title: 'Array links article',
            links: [{ rel: 'self', href: 'https://example.com/array-links/1' }],
            description: 'URL only in links array.'
          }
        ]
      end

      it 'resolves href through ValueFinder so detector and normalizer agree' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Array links article',
            description: 'URL only in links array.',
            url: Html2rss::Url.from_absolute('https://example.com/array-links/1')
          )
        )
      end
    end

    context 'with a flat array of title/url objects' do
      let(:parsed_body) do
        [
          { title: 'Listing one', url: '/items/1', description: 'From a JSON array.' },
          { title: 'Listing two', url: 'https://example.com/items/2' }
        ]
      end

      it 'discovers articles via JsonState' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'Listing one',
            description: 'From a JSON array.',
            url: Html2rss::Url.from_relative('/items/1', base_url)
          ),
          a_hash_including(
            title: 'Listing two',
            url: Html2rss::Url.from_absolute('https://example.com/items/2')
          )
        )
      end
    end

    context 'with an array entry that normalises to nothing' do
      let(:parsed_body) { [{ title: 'Kept', url: '/kept' }, { title: 'Dropped' }] }

      it 'yields only usable articles' do
        expect(articles).to contain_exactly(a_hash_including(title: 'Kept'))
      end
    end

    context 'with WordPress-style rendered title on a non-feed document' do
      let(:parsed_body) do
        [
          {
            title: { rendered: 'How to build a feed' },
            excerpt: { rendered: '<p>A short excerpt.</p>' },
            link: '/feed-reader'
          }
        ]
      end

      it 'unwraps rendered scalars via JsonState', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
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

    context 'with a non-article object' do
      let(:parsed_body) { { status: 'ok', count: 0 } }

      it 'yields nothing' do
        expect(articles).to be_empty
      end
    end

    context 'with a Nokogiri document' do
      let(:parsed_body) { Nokogiri::HTML('<html><body></body></html>') }

      it 'yields nothing' do
        expect(articles).to be_empty
      end
    end
  end

  describe '#json_feed?' do
    subject(:articles) { described_class.new(parsed_body, url: base_url).each.to_a }

    context 'with a JSON Feed 1.1 document' do
      let(:parsed_body) do
        { version: 'https://jsonfeed.org/version/1.1', items: [{ url: 'https://example.com/f', content_text: 'Feed body' }] }
      end

      it 'maps the item through the JSON Feed path' do
        expect(articles).to contain_exactly(a_hash_including(description: 'Feed body', id: 'https://example.com/f'))
      end
    end

    context 'with a Hash body that has no JSON Feed version' do
      let(:parsed_body) { { items: [{ title: 'Plain', url: 'https://example.com/f', content_text: 'Feed body' }] } }

      it 'does not map content_text as a JSON Feed item', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(articles.first).not_to include(:description)
      end
    end

    context 'with an Array body' do
      let(:parsed_body) { [{ title: 'Listed', url: 'https://example.com/listed' }] }

      it 'walks the listing without treating it as a feed' do
        expect(articles).to contain_exactly(a_hash_including(title: 'Listed'))
      end
    end

    context 'when items is not an array' do
      let(:parsed_body) do
        { version: 'https://jsonfeed.org/version/1.1', title: 'Broken', items: 'not-a-list' }
      end

      it 'falls back to article discovery instead of mapping items' do
        expect(articles).to be_empty
      end
    end
  end

  describe '#resolve_json_feed_url' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) { { version: 'https://jsonfeed.org/version/1.1', items: [item] } }

    context 'with a relative url and no id' do
      let(:item) { { url: '/only-url' } }

      it 'resolves the url against the base' do
        expect(articles.first).to include(url: Html2rss::Url.from_absolute('https://example.com/only-url'))
      end
    end

    context 'with a url that differs from the id' do
      let(:item) { { url: 'https://example.com/url-wins', id: 'https://example.com/other' } }

      it 'prefers the item url over the id' do
        expect(articles.first).to include(url: Html2rss::Url.from_absolute('https://example.com/url-wins'))
      end
    end

    context 'with an absolute id and no url' do
      let(:item) { { id: 'https://example.com/id-only', title: 'Id only' } }

      it 'falls back to the id as the article url' do
        expect(articles.first).to include(url: Html2rss::Url.from_absolute('https://example.com/id-only'))
      end
    end

    context 'with neither url nor id' do
      let(:item) { { title: 'Orphan' } }

      it 'skips the item' do
        expect(articles).to be_empty
      end
    end
  end

  describe '#absolute_url' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) { { version: 'https://jsonfeed.org/version/1.1', items: [item] } }

    context 'with an absolute id and no url' do
      let(:item) { { id: 'https://example.com/id-only', title: 'Id only' } }

      it 'uses the id as the article url' do
        expect(articles.first).to include(url: Html2rss::Url.from_absolute('https://example.com/id-only'))
      end
    end

    context 'with neither url nor id' do
      let(:item) { { title: 'Orphan' } }

      it 'skips the item' do
        expect(articles).to be_empty
      end
    end
  end

  describe '#resolve_optional_url' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) { { version: 'https://jsonfeed.org/version/1.1', items: [{ url: 'https://example.com/a', image: '/img/cover.jpg' }] } }

    it 'resolves a relative image against the base url' do
      expect(articles.first).to include(image: Html2rss::Url.from_absolute('https://example.com/img/cover.jpg'))
    end
  end

  describe '#string' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) do
      { version: 'https://jsonfeed.org/version/1.1',
        items: [{ url: 'https://example.com/s', title: 42, id: '  padded-id  ' }] }
    end

    it 'coerces numbers to trimmed strings', :aggregate_failures do
      expect(articles.first).to include(title: '42', id: 'padded-id')
    end
  end

  describe '#map_json_feed_item' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) do
      {
        version: 'https://jsonfeed.org/version/1.1',
        items: [nil, 'junk', 42, { url: 'https://example.com/valid', title: 'Valid' }]
      }
    end

    it 'skips entries that are not objects' do
      expect(articles).to contain_exactly(a_hash_including(title: 'Valid'))
    end

    context 'with an object that has no resolvable url' do
      let(:feed) do
        {
          version: 'https://jsonfeed.org/version/1.1',
          items: [{ title: 'Orphan' }, { url: 'https://example.com/ok', title: 'Ok' }]
        }
      end

      it 'skips the orphan and keeps the valid item' do
        expect(articles).to contain_exactly(a_hash_including(title: 'Ok'))
      end
    end
  end

  describe '#json_feed_article_hash' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) { { version: 'https://jsonfeed.org/version/1.1', items: [item] } }

    context 'with only a url' do
      let(:item) { { url: 'https://example.com/min' } }

      it 'omits absent fields instead of emitting nil values' do
        expect(articles).to eq(
          [{ url: Html2rss::Url.from_absolute('https://example.com/min'), id: 'https://example.com/min' }]
        )
      end
    end

    context 'with an id that differs from the url and a numeric title' do
      let(:item) { { id: 'urn:example:42', url: 'https://example.com/a', title: 42 } }

      it 'keeps the item id and stringifies the title', :aggregate_failures do
        expect(articles.first).to include(id: 'urn:example:42', title: '42')
      end
    end

    context 'with a relative image' do
      let(:item) { { url: 'https://example.com/a', image: '/img/cover.jpg' } }

      it 'resolves the image against the base url' do
        expect(articles.first).to include(image: Html2rss::Url.from_absolute('https://example.com/img/cover.jpg'))
      end
    end

    context 'with a relative url and a different id' do
      let(:item) { { url: '/rel/1', id: 'https://example.com/other' } }

      it 'prefers the resolved item url over the id' do
        expect(articles.first).to include(url: Html2rss::Url.from_absolute('https://example.com/rel/1'))
      end
    end

    context 'with neither url nor id' do
      let(:item) { { title: 'Orphan', content_text: 'No link' } }

      it 'skips the item' do
        expect(articles).to be_empty
      end
    end
  end

  describe '#json_feed_description' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) { { version: 'https://jsonfeed.org/version/1.1', items: [item] } }

    context 'with blank content_text and HTML content' do
      let(:item) { { url: 'https://example.com/d', content_text: '   ', content_html: '<p>Fallback</p>' } }

      it 'falls back to content_html' do
        expect(articles.first).to include(description: '<p>Fallback</p>')
      end
    end

    context 'with only padded content_html' do
      let(:item) { { url: 'https://example.com/d', content_html: '  <p>Only HTML</p>  ' } }

      it 'trims the HTML description' do
        expect(articles.first).to include(description: '<p>Only HTML</p>')
      end
    end

    context 'with no content fields' do
      let(:item) { { url: 'https://example.com/d' } }

      it 'omits the description' do
        expect(articles.first).not_to include(:description)
      end
    end

    context 'with numeric content_text' do
      let(:item) { { url: 'https://example.com/d', content_text: 42 } }

      it 'stringifies the description' do
        expect(articles.first).to include(description: '42')
      end
    end
  end

  describe '#json_feed_tags' do
    subject(:articles) { described_class.new(feed, url: base_url).each.to_a }

    let(:feed) { { version: 'https://jsonfeed.org/version/1.1', items: [item] } }

    context 'with blank, non-string and repeated tags' do
      let(:item) { { url: 'https://example.com/t', tags: ['news', '', nil, 42, 'news'] } }

      it 'keeps unique non-blank strings' do
        expect(articles.first).to include(categories: %w[news 42])
      end
    end

    context 'with only blank tags' do
      let(:item) { { url: 'https://example.com/t', tags: ['', nil] } }

      it 'omits categories' do
        expect(articles.first).not_to include(:categories)
      end
    end

    context 'with a non-array tags value' do
      let(:item) { { url: 'https://example.com/t', tags: 'news' } }

      it 'omits categories without raising' do
        expect(articles.first).not_to include(:categories)
      end
    end
  end
end
