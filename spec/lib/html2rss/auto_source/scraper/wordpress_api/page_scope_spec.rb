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

    context 'when the page URL is a paginated category archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/category/news/page/2/') }
      let(:html) { '<html><body class="archive category category-7"></body></html>' }

      it 'keeps taxonomy scope and includes the current archive page', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq(
          'categories' => '7',
          'page' => '2'
        )
      end
    end

    context 'when the page URL is a paginated date archive path' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/04/page/2/') }

      it 'keeps date range scope and includes the current archive page' do
        expected_query = { 'after' => '2024-04-01T00:00:00Z', 'before' => '2024-05-01T00:00:00Z', 'page' => '2' }
        expect(page_scope).to have_attributes(fetchable?: true, query: expected_query)
      end
    end

    context 'when the page URL uses query-style pagination' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/04/?paged=3') }

      it 'maps paged query values to the posts page query' do
        expected_query = { 'after' => '2024-04-01T00:00:00Z', 'before' => '2024-05-01T00:00:00Z', 'page' => '3' }
        expect(page_scope).to have_attributes(fetchable?: true, query: expected_query)
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

    context 'when the page is a non-archive singular page' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/about/') }
      let(:html) { '<html><body class="page page-id-2"></body></html>' }

      it 'treats the page as unsafe for an unscoped posts follow-up', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:non_archive)
        expect(page_scope.query).to eq({})
      end
    end
  end
end
