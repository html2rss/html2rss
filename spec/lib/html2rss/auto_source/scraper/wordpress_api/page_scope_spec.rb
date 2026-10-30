# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi::PageScope do
  subject(:page_scope) { described_class.from(parsed_body:, url:) }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/') }
  let(:html) { '<html><body></body></html>' }
  let(:parsed_body) { Nokogiri::HTML(html) }

  describe Html2rss::AutoSource::Scraper::WordpressApi::PageScope::DateArchiveRange do
    describe '.from_segments' do
      it 'maps year/month/day segments to exclusive after/before bounds' do
        expect(described_class.from_segments(%w[2024 02 29])).to eq(
          'after' => '2024-02-29T00:00:00Z',
          'before' => '2024-03-01T00:00:00Z'
        )
      end

      it 'returns nil for calendar-invalid date segments' do
        expect(described_class.from_segments(%w[2023 02 29])).to be_nil
      end

      it 'returns nil when segments are not a date archive path' do
        expect(described_class.from_segments(%w[category news])).to be_nil
      end
    end

    describe '.path?' do
      it 'is true for shape-valid date segments even when the calendar date is invalid' do
        expect(described_class.path?(%w[2023 02 29])).to be(true)
      end

      it 'is false for non-date archive segments' do
        expect(described_class.path?(%w[category news])).to be(false)
      end
    end
  end

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

    context 'when the body advertises an author archive id' do
      let(:html) { '<html><body class="author author-5"></body></html>' }

      it 'scopes the posts query to the author', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.reason).to eq(:archive)
        expect(page_scope.query).to eq('author' => '5')
      end
    end

    context 'when an archive body class lacks an id' do
      let(:html) { '<html><body class="tag"></body></html>' }

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
      end
    end

    context 'when an author archive is only identified by its URL path' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/author/jane/') }

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
      end
    end

    context 'when the body is a generic archive' do
      let(:html) { '<html><body class="archive"></body></html>' }

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
      end
    end

    context 'when a body class only resembles a singular marker' do
      let(:html) { '<html><body class="postid-abc"></body></html>' }

      it 'keeps the page unscoped and fetchable', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.reason).to eq(:unscoped)
      end
    end

    %w[page-id-12 postid-3 single singular attachment].each do |body_class|
      context "when the body class is #{body_class}" do
        let(:html) { %(<html><body class="#{body_class}"></body></html>) }

        it 'treats the page as a non-archive singular page', :aggregate_failures do
          expect(page_scope).not_to be_fetchable
          expect(page_scope.reason).to eq(:non_archive)
        end
      end
    end

    context 'when the URL carries a zero paged query' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/?paged=0') }

      it 'ignores the page number' do
        expect(page_scope.query).to eq({})
      end
    end

    context 'when a category archive is paginated by query' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/?paged=3') }
      let(:html) { '<html><body class="category category-7"></body></html>' }

      it 'keeps the archive scope and adds the page', :aggregate_failures do
        expect(page_scope.reason).to eq(:archive)
        expect(page_scope.query).to eq('categories' => '7', 'page' => '3')
      end
    end

    context 'when an unsupported archive is paginated' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/tag/news/page/2/') }

      it 'does not add pagination to the unsafe scope', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
        expect(page_scope.query).to eq({})
      end
    end

    context 'when the body advertises a tag archive id' do
      let(:html) { '<html><body class="tag tag-9"></body></html>' }

      it 'scopes the posts query to the tag', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.reason).to eq(:archive)
        expect(page_scope.query).to eq('tags' => '9')
      end
    end

    context 'when a category archive is only identified by its URL path' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/category/news/') }

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
      end
    end

    context 'when a tag archive is only identified by its URL path' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/tag/news/') }

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
      end
    end

    context 'when the body is a date archive without a parseable date' do
      let(:html) { '<html><body class="date"></body></html>' }

      it 'treats the archive as unsupported', :aggregate_failures do
        expect(page_scope).not_to be_fetchable
        expect(page_scope.reason).to eq(:unsupported_archive)
      end
    end

    context 'when a body class merely ends with a singular marker' do
      let(:html) { '<html><body class="xpostid-3"></body></html>' }

      it 'keeps the page unscoped and fetchable', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.reason).to eq(:unscoped)
      end
    end

    context 'when the URL has a page segment without a number' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/page/abc/') }

      it 'does not treat the segment as pagination', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq({})
      end
    end

    context 'when the URL is a bare page segment' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/page/2/') }

      it 'applies the path page number to an unscoped page', :aggregate_failures do
        expect(page_scope.reason).to eq(:unscoped)
        expect(page_scope.query).to eq('page' => '2')
      end
    end

    %w[abc 2a -1].each do |value|
      context "when the paged query is #{value}" do
        let(:url) { Html2rss::Url.from_absolute("https://example.com/blog/?paged=#{value}") }

        it 'ignores the page number' do
          expect(page_scope.query).to eq({})
        end
      end
    end

    context 'when the canonical href is blank' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/') }
      let(:html) { '<html><head><link rel="canonical" href=""></head><body></body></html>' }

      it 'derives the scope from the page URL', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq('after' => '2024-01-01T00:00:00Z', 'before' => '2025-01-01T00:00:00Z')
      end
    end

    context 'when the canonical href is malformed' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/') }
      let(:html) { '<html><head><link rel="canonical" href="://bad url"></head><body></body></html>' }

      it 'falls back to the page URL', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq('after' => '2024-01-01T00:00:00Z', 'before' => '2025-01-01T00:00:00Z')
      end
    end

    context 'when the canonical href has surrounding whitespace' do
      let(:html) { '<html><head><link rel="canonical" href="  https://example.com/2023/  "></head><body></body></html>' }

      it 'uses the trimmed same-origin canonical date archive', :aggregate_failures do
        expect(page_scope).to be_fetchable
        expect(page_scope.query).to eq('after' => '2023-01-01T00:00:00Z', 'before' => '2024-01-01T00:00:00Z')
      end
    end

    context 'when the canonical href is on another port' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/') }
      let(:html) { '<html><head><link rel="canonical" href="https://example.com:8443/2023/"></head><body></body></html>' }

      it 'ignores the cross-port canonical and keeps the page URL scope' do
        expect(page_scope.query).to eq('after' => '2024-01-01T00:00:00Z', 'before' => '2025-01-01T00:00:00Z')
      end
    end

    context 'when the canonical href uses another scheme' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/') }
      let(:html) { '<html><head><link rel="canonical" href="http://example.com/2023/"></head><body></body></html>' }

      it 'ignores the cross-scheme canonical and keeps the page URL scope' do
        expect(page_scope.query).to eq('after' => '2024-01-01T00:00:00Z', 'before' => '2025-01-01T00:00:00Z')
      end
    end

    it 'freezes the scope and its query', :aggregate_failures do
      expect(page_scope).to be_frozen
      expect(page_scope.query).to be_frozen
    end
  end
end
