# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi do
  subject(:instance) { described_class.new(parsed_body, url:, request_session:) }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/blog') }
  let(:request_session) { instance_double(Html2rss::RequestSession) }
  let(:fixture_root) { File.expand_path('../../../../fixtures/auto_source/wordpress_api', __dir__) }
  let(:index_html) { File.read(File.join(fixture_root, 'index.html')) }
  let(:posts_json) { File.read(File.join(fixture_root, 'posts.json')) }
  let(:parsed_body) { Nokogiri::HTML(index_html) }

  describe '.articles?' do
    it 'returns true when the page exposes the WordPress API link' do
      expect(described_class.articles?(parsed_body)).to be(true)
    end

    it 'returns false when the page does not expose the WordPress API link' do
      html = Nokogiri::HTML('<html><head></head><body></body></html>')

      expect(described_class.articles?(html)).to be(false)
    end
  end

  describe '#each' do
    subject(:articles) { instance.each.to_a }

    let(:api_response) do
      Html2rss::RequestService::Response.new(
        body: posts_json,
        url: Html2rss::Url.from_absolute(
          'https://example.com/wp-json/wp/v2/posts?_fields=id,title,excerpt,content,link,date,categories&per_page=100'
        ),
        headers: { 'content-type' => 'application/json' }
      )
    end

    before do
      allow(request_session).to receive(:follow_up).and_return(api_response)
    end

    it 'requests the posts endpoint' do # rubocop:disable RSpec/ExampleLength
      articles

      expect(request_session).to have_received(:follow_up).with(
        url: api_response.url,
        relation: :auto_source,
        origin_url: url
      )
    end

    it 'normalises API posts into article hashes' do # rubocop:disable RSpec/ExampleLength
      expect(articles).to contain_exactly(
        match(
          id: '/2024/04/wordpress-api-post/',
          title: 'WordPress API post',
          description: '<p>Full content from the API.</p>',
          url: Html2rss::Url.from_absolute('https://example.com/2024/04/wordpress-api-post/'),
          published_at: '2024-04-01T12:00:00',
          categories: match_array(%w[7 9])
        ),
        match(
          id: '/2024/04/excerpt-only-post/',
          title: 'Excerpt only post',
          description: '<p>Excerpt fallback content.</p>',
          url: Html2rss::Url.from_absolute('https://example.com/2024/04/excerpt-only-post/'),
          published_at: '2024-04-02T08:15:00',
          categories: be_empty
        )
      )
    end

    it 'preserves the expected article shape for each mapped post' do
      expect(articles).to all(include(:id, :title, :description, :url, :published_at, :categories))
    end

    it 'uses the canonical article path as the article id' do
      expect(articles.map { _1[:id] }).to eq(['/2024/04/wordpress-api-post/', '/2024/04/excerpt-only-post/'])
    end

    context 'when the request session is unavailable' do
      let(:request_session) { nil }

      it 'returns no articles' do
        expect(articles).to eq([])
      end
    end

    context 'when the WordPress API returns query-style permalinks' do
      let(:posts_json) do
        <<~JSON
          [
            {
              "id": 123,
              "title": { "rendered": "First query permalink post" },
              "content": { "rendered": "<p>First body</p>" },
              "excerpt": { "rendered": "<p>First excerpt</p>" },
              "link": "https://example.com/?p=123",
              "date": "2024-04-01T12:00:00",
              "categories": []
            },
            {
              "id": 456,
              "title": { "rendered": "Second query permalink post" },
              "content": { "rendered": "<p>Second body</p>" },
              "excerpt": { "rendered": "<p>Second excerpt</p>" },
              "link": "https://example.com/?p=456",
              "date": "2024-04-02T12:00:00",
              "categories": []
            }
          ]
        JSON
      end

      it 'keeps distinct ids for query-based permalinks' do
        expect(articles.map { _1[:id] }).to eq(['/?p=123', '/?p=456'])
      end
    end
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers
