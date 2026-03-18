# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi::PageScope do
  subject(:page_scope) { described_class.from(parsed_body:, url:) }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/') }
  let(:html) { '<html><body></body></html>' }
  let(:parsed_body) { Nokogiri::HTML(html) }

  describe '.from' do
    context 'when the page URL is a yearly archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/') }

      it 'derives the year range from the archive path', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-01-01T00:00:00Z',
          'before' => '2025-01-01T00:00:00Z'
        )
      end
    end

    context 'when the page URL is a monthly archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/12/') }

      it 'crosses the year boundary when calculating the next month', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-12-01T00:00:00Z',
          'before' => '2025-01-01T00:00:00Z'
        )
      end
    end

    context 'when the page URL is a daily archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/02/29/') }

      it 'derives the day range for leap day archives', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-02-29T00:00:00Z',
          'before' => '2024-03-01T00:00:00Z'
        )
      end
    end

    context 'when the page URL is the last day of a month' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/01/31/') }

      it 'crosses the month boundary when calculating the next day', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-01-31T00:00:00Z',
          'before' => '2024-02-01T00:00:00Z'
        )
      end
    end

    context 'when the page advertises an invalid non-leap date archive' do
      let(:html) do
        '<html><head><link rel="canonical" href="https://example.com/2023/02/29/" /></head>' \
          '<body class="archive date"></body></html>'
      end

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.query).to eq({})
      end
    end

    context 'when the page exposes a canonical date archive' do
      let(:html) do
        '<html><head><link rel="canonical" href="https://example.com/2024/02/29/" /></head>' \
          '<body class="archive date"></body></html>'
      end

      it 'prefers the canonical URL over the current request URL', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-02-29T00:00:00Z',
          'before' => '2024-03-01T00:00:00Z'
        )
      end
    end

    context 'when the page URL is a subdirectory date archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/2024/04/') }

      it 'derives the date range from the archive segment sequence', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-04-01T00:00:00Z',
          'before' => '2024-05-01T00:00:00Z'
        )
      end
    end

    context 'when the page exposes a cross-origin canonical date archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/04/') }
      let(:html) do
        '<html><head><link rel="canonical" href="https://elsewhere.example.net/2024/02/29/" /></head>' \
          '<body class="archive date"></body></html>'
      end

      it 'ignores the cross-origin canonical and keeps the current page scope', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'after' => '2024-04-01T00:00:00Z',
          'before' => '2024-05-01T00:00:00Z'
        )
      end
    end
  end
end
