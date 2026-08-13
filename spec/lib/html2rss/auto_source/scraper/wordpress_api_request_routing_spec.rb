# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi do
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

  [
    {
      description: 'when the api link href is blank',
      html: '<html><head><link rel="https://api.w.org/" href="" /></head></html>',
      log_level: :debug,
      log_match: /without a usable API root/
    },
    {
      description: 'when the api link href is invalid',
      html: '<html><head><link rel="https://api.w.org/" href="://bad url" /></head></html>',
      log_level: :warn,
      log_match: /WordPress API/
    }
  ].each do |example|
    context example.fetch(:description) do
      let(:url) { Html2rss::Url.from_absolute('https://example.com/blog') }
      let(:parsed_body) { Nokogiri::HTML(example.fetch(:html)) }

      before { allow(Html2rss::Log).to receive(example.fetch(:log_level)) }

      it 'returns no articles, skips follow-up, and logs', :aggregate_failures do
        articles = described_class.new(parsed_body, url:, request_session:).each.to_a

        expect(articles).to eq([])
        expect(request_session).not_to have_received(:follow_up)
        expect(Html2rss::Log).to have_received(example.fetch(:log_level)).with(example.fetch(:log_match))
      end
    end
  end

  # rubocop:disable RSpec/ExampleLength
  [
    {
      description: 'preserves the query-style api root when requesting posts',
      html: '<html><head>' \
            '<link rel="https://api.w.org/" href="https://example.com/index.php?rest_route=/" />' \
            '</head></html>',
      expected_url:
        'https://example.com/index.php?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&per_page=100&rest_route=%2Fwp%2Fv2%2Fposts'
    },
    {
      description: 'preserves the wp-json root when requesting posts',
      html: '<html><head>' \
            '<link rel="https://api.w.org/" href="https://example.com/wp-json" />' \
            '</head></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&per_page=100'
    },
    {
      description: 'preserves query params when requesting posts',
      html: '<html><head>' \
            '<link rel="https://api.w.org/" href="https://example.com/wp-json?lang=de" />' \
            '</head></html>',
      expected_path: '/wp-json/wp/v2/posts',
      expected_query: { 'lang' => 'de', 'per_page' => '100' }
    },
    {
      description: 'scopes the posts request to the category archive term',
      page_url: 'https://example.com/category/news/',
      html: '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
            '<body class="archive category category-news category-7"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&categories=7&per_page=100'
    },
    {
      description: 'scopes the posts request to the tag archive term',
      page_url: 'https://example.com/tag/ruby/',
      html: '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
            '<body class="archive tag tag-ruby tag-9"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&per_page=100&tags=9'
    },
    {
      description: 'scopes the posts request to the author archive',
      page_url: 'https://example.com/author/jane/',
      html: '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head>' \
            '<body class="archive author author-jane author-3"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&author=3&per_page=100'
    },
    {
      description: 'scopes the posts request to the date window',
      page_url: 'https://example.com/2024/04/',
      html: '<html><head>' \
            '<link rel="canonical" href="https://example.com/2024/04/" />' \
            '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
            '</head><body class="archive date"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&after=2024-04-01T00%3A00%3A00Z&before=2024-05-01T00%3A00%3A00Z&per_page=100'
    },
    {
      description: 'prefers the canonical date scope when requesting posts',
      html: '<html><head>' \
            '<link rel="canonical" href="https://example.com/2024/02/29/" />' \
            '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
            '</head><body class="archive date"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&after=2024-02-29T00%3A00%3A00Z&before=2024-03-01T00%3A00%3A00Z&per_page=100'
    },
    {
      description: 'scopes the posts request to the subdirectory date window',
      page_url: 'https://example.com/blog/2024/04/',
      html: '<html><head>' \
            '<link rel="canonical" href="https://example.com/blog/2024/04/" />' \
            '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
            '</head><body class="archive date"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&after=2024-04-01T00%3A00%3A00Z&before=2024-05-01T00%3A00%3A00Z&per_page=100'
    },
    {
      description: 'ignores the cross-origin canonical when deriving the date scope',
      page_url: 'https://example.com/2024/04/',
      html: '<html><head>' \
            '<link rel="canonical" href="https://elsewhere.example.net/2024/02/29/" />' \
            '<link rel="https://api.w.org/" href="https://example.com/wp-json/" />' \
            '</head><body class="archive date"></body></html>',
      expected_url:
        'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle%2Cexcerpt%2Ccontent%2Clink%2Cdate%2Ccategories' \
        '&after=2024-04-01T00%3A00%3A00Z&before=2024-05-01T00%3A00%3A00Z&per_page=100'
    }
  ].each do |example|
    it example.fetch(:description) do
      page_url = Html2rss::Url.from_absolute(example.fetch(:page_url, 'https://example.com/blog'))
      described_class.new(Nokogiri::HTML(example.fetch(:html)), url: page_url, request_session:).each.to_a

      if example.key?(:expected_query)
        expect(request_session).to have_received(:follow_up).with(
          hash_including(
            url: satisfy do |request_url|
              request_url.path == example.fetch(:expected_path) &&
                example.fetch(:expected_query).all? { |key, value| request_url.query_values[key] == value }
            end
          )
        )
      else
        expect(request_session).to have_received(:follow_up).with(
          url: Html2rss::Url.from_absolute(example.fetch(:expected_url)),
          relation: :auto_source,
          origin_url: page_url
        )
      end
    end
  end
  # rubocop:enable RSpec/ExampleLength
end
