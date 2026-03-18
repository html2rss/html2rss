# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi do
  subject(:articles) { described_class.new(parsed_body, url:, request_session:).each.to_a }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/blog') }
  let(:request_session) { instance_double(Html2rss::RequestSession) }
  let(:empty_api_response) do
    Html2rss::RequestService::Response.new(
      body: '[]',
      url: Html2rss::Url.from_absolute(
        'https://example.com/wp-json/wp/v2/posts?_fields=id,title,excerpt,content,link,date,categories&per_page=100'
      ),
      headers: { 'content-type' => 'application/json' }
    )
  end

  before do
    allow(request_session).to receive(:follow_up).and_return(empty_api_response)
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
    let(:empty_api_response) do
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
        url: empty_api_response.url,
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
    let(:empty_api_response) do
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
        url: empty_api_response.url,
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
end
