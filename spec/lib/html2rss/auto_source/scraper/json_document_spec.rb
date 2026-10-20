# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonDocument do
  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }

  describe '.articles?' do
    it 'is never detectable from HTML alone' do
      expect(described_class).not_to be_articles(Nokogiri::HTML('<html></html>'))
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
end
