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

    let(:empty_api_response) do
      Html2rss::RequestService::Response.new(
        body: '[]',
        url: Html2rss::Url.from_absolute(
          'https://example.com/wp-json/wp/v2/posts?_fields=id,title,excerpt,content,link,date,categories&per_page=100'
        ),
        headers: { 'content-type' => 'application/json' }
      )
    end
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
      expected_articles = [
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
      ]

      expect(articles).to match_array(expected_articles)
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

    context 'when the api link href is blank' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><link rel="https://api.w.org/" href="" /></head></html>')
      end

      before do
        allow(Html2rss::Log).to receive(:debug)
      end

      it 'returns no articles, skips follow-up requests, and logs the missing api root', :aggregate_failures do
        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(:debug).with(/without a usable API root/)
      end
    end

    context 'when the api link href is invalid' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><link rel="https://api.w.org/" href="://bad url" /></head></html>')
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns no articles and logs a warning', :aggregate_failures do
        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(:warn).with(/WordPress API/)
      end
    end

    context 'when the advertised api root uses rest_route query params' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="https://api.w.org/" href="https://example.com/index.php?rest_route=/" />' \
          '</head></html>'
        )
      end
      let(:api_response) do
        Html2rss::RequestService::Response.new(
          body: '[]',
          url: Html2rss::Url.from_absolute(
            'https://example.com/index.php?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&per_page=100&rest_route=%2Fwp%2Fv2%2Fposts'
          ),
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'preserves the query-style api root when requesting posts' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: api_response.url,
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the advertised api root omits the trailing slash' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json" />' \
          '</head></html>'
        )
      end
      let(:api_response) do
        Html2rss::RequestService::Response.new(
          body: '[]',
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&per_page=100'
          ),
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'preserves the wp-json root when requesting posts' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: api_response.url,
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the advertised api root carries additional query params' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json?lang=de" />' \
          '</head></html>'
        )
      end

      it 'preserves query params when requesting posts' do # rubocop:disable RSpec/ExampleLength
        articles

        expect(request_session).to have_received(:follow_up).with(
          hash_including(
            url: satisfy do |request_url|
              request_url.path == '/wp-json/wp/v2/posts' &&
                request_url.query_values['lang'] == 'de' &&
                request_url.query_values['per_page'] == '100'
            end
          )
        )
      end
    end

    context 'when the page is a category archive with a term id signal' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/category/news/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
          '<body class="archive category category-news category-7"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'scopes the posts request to the category archive term' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&categories=7&per_page=100'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the page is a tag archive with a term id signal' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/tag/ruby/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
          '<body class="archive tag tag-ruby tag-9"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'scopes the posts request to the tag archive term' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&per_page=100&tags=9'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the page is an author archive with an author id signal' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/author/jane/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
          '<body class="archive author author-jane author-3"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'scopes the posts request to the author archive' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&author=3&per_page=100'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the page is a date archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/04/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="canonical" href="https://example.com/2024/04/" />' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
          '</head><body class="archive date"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'scopes the posts request to the date window' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&after=2024-04-01T00%3A00%3A00Z&before=2024-05-01T00%3A00%3A00Z&per_page=100'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the date archive is only exposed through the canonical URL' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="canonical" href="https://example.com/2024/02/29/" />' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
          '</head><body class="archive date"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'prefers the canonical date scope when requesting posts' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&after=2024-02-29T00%3A00%3A00Z&before=2024-03-01T00%3A00%3A00Z&per_page=100'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the page is a subdirectory date archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/blog/2024/04/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="canonical" href="https://example.com/blog/2024/04/" />' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
          '</head><body class="archive date"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'scopes the posts request to the subdirectory date window' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&after=2024-04-01T00%3A00%3A00Z&before=2024-05-01T00%3A00%3A00Z&per_page=100'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the page exposes a cross-origin canonical date archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/2024/04/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="canonical" href="https://elsewhere.example.net/2024/02/29/" />' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
          '</head><body class="archive date"></body></html>'
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(empty_api_response)
      end

      it 'ignores the cross-origin canonical when deriving the date scope' do # rubocop:disable RSpec/ExampleLength
        articles
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories&after=2024-04-01T00%3A00%3A00Z&before=2024-05-01T00%3A00%3A00Z&per_page=100'
          ),
          relation: :auto_source,
          origin_url: url
        )
      end
    end

    context 'when the canonical date archive is invalid' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="canonical" href="https://example.com/2023/02/29/" />' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
          '</head><body class="archive date"></body></html>'
        )
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns no articles, skips follow-up requests, and logs the unsafe scope', :aggregate_failures do
        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(:warn).with(/unable to derive safe WordPress archive scope/)
      end
    end

    context 'when the page is an archive without a safe scope signal' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/category/news/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
          '<body class="archive category category-news"></body></html>'
        )
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns no articles, skips follow-up requests, and logs the unsafe scope', :aggregate_failures do
        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(:warn).with(/unable to derive safe WordPress archive scope/)
      end
    end

    context 'when the page is not an archive' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/about/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
          '<body class="page page-id-2"></body></html>'
        )
      end

      before do
        allow(Html2rss::Log).to receive(:debug)
      end

      it 'does not fall back to the unscoped posts collection', :aggregate_failures do
        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(:debug).with(/without a safe WordPress archive scope/)
      end
    end

    context 'when the archive is only detectable from the URL path' do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/category/news/') }
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
          '<body></body></html>'
        )
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'does not fall back to the unscoped posts collection', :aggregate_failures do
        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(:warn).with(/unable to derive safe WordPress archive scope/)
      end
    end

    context 'when the posts response content type is unsupported' do
      let(:api_response) do
        Html2rss::RequestService::Response.new(
          body: 'not-json',
          url: Html2rss::Url.from_absolute('https://example.com/wp-json/wp/v2/posts'),
          headers: { 'content-type' => 'text/plain' }
        )
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns no articles and logs a warning', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn).with(/unsupported WordPress API posts content type/i)
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

    context 'when the follow-up request exceeds the request budget' do
      before do
        allow(request_session).to receive(:follow_up)
          .and_raise(Html2rss::RequestService::RequestBudgetExceeded, 'Request budget exhausted')
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns no articles and logs the operational failure', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn).with(/failed to fetch WordPress API posts/)
      end
    end

    context 'when the follow-up request raises an unexpected error' do
      before do
        allow(request_session).to receive(:follow_up).and_raise(StandardError, 'boom')
      end

      it 're-raises the defect instead of degrading it' do
        expect { articles }.to raise_error(StandardError, 'boom')
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
