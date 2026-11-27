# frozen_string_literal: true

RSpec.describe Html2rss::Extraction::Result do
  let(:full) do
    Html2rss::Article.new(
      url: 'https://example.com/a', title: 'A headline', description: 'Body text', image: 'https://example.com/a.jpg',
      author: 'Ada', published_at: '2026-01-02T03:04:05+00:00', categories: ['News', ' News ', 'Tech'], media: true,
      enclosures: [{ url: Html2rss::Url.from_absolute('https://example.com/a.mp3'), type: 'audio/mpeg',
                     bytes_length: 12, duration: 34 }],
      scraper: Html2rss::AutoSource::Scraper::Schema
    )
  end
  let(:bare) { Html2rss::Article.new(title: 'No link', scraper: Html2rss::AutoSource::Scraper::SemanticHtml) }

  let(:full_data) do
    { url: 'https://example.com/a', title: 'A headline', description: 'Body text',
      image: 'https://example.com/a.jpg', author: 'Ada', guid: full.guid, published_at: '2026-01-02T03:04:05+00:00',
      categories: %w[News Tech], media: true, scraper: 'AutoSource::Schema',
      enclosures: [{ url: 'https://example.com/a.mp3', type: 'audio/mpeg', bytes_length: 12, duration: 34 }] }
  end

  describe '.ok' do
    it 'holds one plain hash per article', :aggregate_failures do
      result = described_class.ok([full])

      expect(result).to have_attributes(status: :ok, error_kind: nil, requests: [])
      expect(result.articles).to eq([full_data])
    end

    it 'leaves absent values nil' do
      result = described_class.ok([bare])

      expect(result.articles.first).to include(url: nil, image: nil, published_at: nil, enclosures: [], media: false)
    end

    it 'is empty without articles' do
      expect(described_class.ok([])).to have_attributes(status: :empty, articles: [], error_kind: nil)
    end
  end

  describe '.needs_requests' do
    it 'holds the wanted requests as plain hashes, without articles' do
      request = Html2rss::Extraction::Exchange::Request.new(
        id: 'auto_source https://example.com/feed', url: 'https://example.com/feed', relation: :auto_source,
        origin_url: 'https://example.com/'
      )

      expect(described_class.needs_requests([request]))
        .to have_attributes(status: :needs_requests, articles: [], error_kind: nil, requests: [request.to_h])
    end
  end

  describe '.failure' do
    it 'carries the error kind of the failure' do
      error = Html2rss::RequestService::RequestTimedOut.new('slow')

      expect(described_class.failure(error))
        .to have_attributes(status: :error, articles: [], error_kind: Html2rss::ErrorKind[:timeout])
    end
  end
end
