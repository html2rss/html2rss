# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi::PostsEndpoint do
  subject(:posts_endpoint) do
    described_class.resolve(
      parsed_body:,
      page_url:,
      page_scope:,
      posts_query:,
      logger:
    )
  end

  let(:page_url) { Html2rss::Url.from_absolute('https://example.com/blog/') }
  let(:parsed_body) do
    Nokogiri::HTML('<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json/" /></head></html>')
  end
  let(:page_scope) do
    instance_double(Html2rss::AutoSource::Scraper::WordpressApi::PageScope, fetchable?: true, reason: :unscoped)
  end
  let(:posts_query) { { '_fields' => 'id,title', 'per_page' => '100' } }
  let(:logger) { instance_double(Logger, warn: nil, debug: nil) }

  describe '.resolve' do
    context 'when the page advertises a collection-style API root' do
      it 'builds the posts collection URL' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute('https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle&per_page=100')
        )
      end
    end

    context 'when the page advertises a query-style API root' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="https://api.w.org/" href="https://example.com/index.php?rest_route=/" />' \
          '</head></html>'
        )
      end

      it 'preserves the query-style API root' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute(
            'https://example.com/index.php?_fields=id%2Ctitle&per_page=100&rest_route=%2Fwp%2Fv2%2Fposts'
          )
        )
      end
    end

    context 'when posts query includes a paginated archive page' do
      let(:posts_query) { { '_fields' => 'id,title', 'per_page' => '100', 'page' => '2' } }

      it 'preserves pagination for collection-style API roots' do
        expect(posts_endpoint.query_values).to include('_fields' => 'id,title', 'per_page' => '100', 'page' => '2')
      end
    end

    context 'when query-style API roots receive paginated archive queries' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="https://api.w.org/" href="https://example.com/index.php?rest_route=/" />' \
          '</head></html>'
        )
      end
      let(:posts_query) { { '_fields' => 'id,title', 'per_page' => '100', 'page' => '3' } }

      it 'preserves pagination for query-style API roots' do
        expected_query = { '_fields' => 'id,title', 'per_page' => '100', 'page' => '3', 'rest_route' => '/wp/v2/posts' }
        expect(posts_endpoint.query_values).to include(expected_query)
      end
    end

    context 'when the API root carries additional query params' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="https://api.w.org/" href="https://example.com/wp-json?lang=de" /></head></html>'
        )
      end

      it 'preserves the existing query params' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle&lang=de&per_page=100'
          )
        )
      end
    end

    context 'when another query param value mentions rest_route' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head>' \
          '<link rel="https://api.w.org/" href="https://example.com/wp-json?redirect=rest_route=/wp/v2/posts" />' \
          '</head></html>'
        )
      end

      it 'still treats the API root as collection-style' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute(
            'https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle&per_page=100&redirect=rest_route%3D%2Fwp%2Fv2%2Fposts'
          )
        )
      end
    end

    context 'when the page scope is not safely fetchable' do
      let(:page_scope) do
        instance_double(
          Html2rss::AutoSource::Scraper::WordpressApi::PageScope,
          fetchable?: false,
          reason: :unsupported_archive
        )
      end

      it 'returns nil and logs the unsafe scope', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:warn).with(/unable to derive safe WordPress archive scope/)
      end
    end

    context 'when the page is a non-archive page' do
      let(:page_scope) do
        instance_double(
          Html2rss::AutoSource::Scraper::WordpressApi::PageScope,
          fetchable?: false,
          reason: :non_archive
        )
      end

      it 'returns nil and logs a debug message', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:debug).with(/without a safe WordPress archive scope/)
      end
    end

    context 'when the API href is blank' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><link rel="https://api.w.org/" href="" /></head></html>')
      end

      it 'returns nil and logs the missing API root', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:debug).with(/without a usable API root/)
      end
    end

    context 'when the API href is invalid' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><link rel="https://api.w.org/" href="://bad url" /></head></html>')
      end

      it 'returns nil and logs the invalid API root', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:warn).with(/invalid WordPress API endpoint/)
      end
    end
  end

  describe '.resolve with no injected logger' do
    it 'logs through the shared Html2rss logger', :aggregate_failures do
      allow(Html2rss::Log).to receive(:debug)
      body = Nokogiri::HTML('<html></html>')
      result = described_class.resolve(parsed_body: body, page_url:, page_scope:, posts_query:)

      expect(result).to be_nil
      expect(Html2rss::Log).to have_received(:debug).with(a_string_including('without a usable API root'))
    end
  end

  describe '#api_root_url' do
    let(:parsed_body) do
      Nokogiri::HTML(%(<html><head><link rel="https://api.w.org/" href="#{api_href}" /></head></html>))
    end
    let(:collection_url) do
      Html2rss::Url.from_absolute('https://example.com/wp-json/wp/v2/posts?_fields=id%2Ctitle&per_page=100')
    end

    context 'when the API href has leading whitespace' do
      let(:api_href) { '  https://example.com/wp-json/' }

      it('resolves the collection URL') { expect(posts_endpoint).to eq(collection_url) }
    end

    context 'when the API href has trailing whitespace' do
      let(:api_href) { "https://example.com/wp-json/ \n" }

      it('resolves the collection URL') { expect(posts_endpoint).to eq(collection_url) }
    end

    context 'when the API href is relative to the page' do
      let(:api_href) { '/wp-json/' }

      it('resolves against the page URL') { expect(posts_endpoint).to eq(collection_url) }
    end

    context 'when the API href is invalid' do
      let(:api_href) { '://bad url' }

      let(:rejected_href_log) do
        %r{\AHtml2rss::AutoSource::Scraper::WordpressApi: invalid WordPress API endpoint "://bad url" \(.+\)\z}
      end

      it 'logs the rejected href and the error', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:warn).with(a_string_matching(rejected_href_log))
      end
    end
  end

  describe '#log_missing_api_root' do
    let(:parsed_body) { Nokogiri::HTML('<html><head><link rel="https://api.w.org/" href="" /></head></html>') }

    it 'logs the missing API root at debug level', :aggregate_failures do
      expect(posts_endpoint).to be_nil
      expect(logger).to have_received(:debug).with(
        'Html2rss::AutoSource::Scraper::WordpressApi: page advertised WordPress API support without a usable API root'
      )
    end
  end

  describe '#fetchable_page_scope?' do
    context 'when the archive scope is unsafe' do
      let(:page_scope) do
        instance_double(
          Html2rss::AutoSource::Scraper::WordpressApi::PageScope, fetchable?: false, reason: :unsupported_archive
        )
      end

      let(:unsafe_scope_log) do
        '{"event_name":"wordpress_api.unsafe_archive_scope","host":"example.com",' \
          '"message":"Html2rss::AutoSource::Scraper::WordpressApi: unable to derive safe WordPress archive ' \
          'scope for https://example.com/blog/"}'
      end

      it 'logs a structured warning naming the host and page', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:warn).with(unsafe_scope_log)
      end
    end

    context 'when the page is a non-archive page' do
      let(:page_scope) do
        instance_double(Html2rss::AutoSource::Scraper::WordpressApi::PageScope, fetchable?: false, reason: :non_archive)
      end

      it 'logs the exact debug message', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:debug).with(
          'Html2rss::AutoSource::Scraper::WordpressApi: page advertised WordPress API support ' \
          'without a safe WordPress archive scope'
        )
      end
    end
  end

  describe '#query_root_posts_url' do
    let(:parsed_body) do
      Nokogiri::HTML(%(<html><head><link rel="https://api.w.org/" href="#{api_href}" /></head></html>))
    end

    context 'when the query-style route is nested' do
      let(:api_href) { 'https://example.com/index.php?rest_route=/api/' }

      it 'appends the posts route below the trimmed route' do
        expect(posts_endpoint.query_values).to include('rest_route' => '/api/wp/v2/posts')
      end
    end

    context 'when the query-style route lacks a leading slash and has repeated trailing slashes' do
      let(:api_href) { 'https://example.com/index.php?rest_route=api//' }

      it 'normalizes the route before appending the posts route' do
        expect(posts_endpoint.query_values).to include('rest_route' => '/api/wp/v2/posts')
      end
    end

    context 'when the query-style route is empty' do
      let(:api_href) { 'https://example.com/index.php?rest_route=' }

      it 'uses the root posts route' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute(
            'https://example.com/index.php?_fields=id%2Ctitle&per_page=100&rest_route=%2Fwp%2Fv2%2Fposts'
          )
        )
      end
    end
  end

  describe '#normalized_api_path' do
    let(:parsed_body) do
      Nokogiri::HTML(%(<html><head><link rel="https://api.w.org/" href="#{api_href}" /></head></html>))
    end

    context 'when the collection API root is nested without a trailing slash' do
      let(:api_href) { 'https://example.com/site/wp-json' }

      it 'keeps the nested segments and adds a trailing slash' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute('https://example.com/site/wp-json/wp/v2/posts?_fields=id%2Ctitle&per_page=100')
        )
      end
    end

    context 'when the collection API root has repeated slashes' do
      let(:api_href) { 'https://example.com//site//wp-json//' }

      it 'collapses the repeated slashes' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute('https://example.com/site/wp-json/wp/v2/posts?_fields=id%2Ctitle&per_page=100')
        )
      end
    end

    context 'when the collection API root is the site root' do
      let(:api_href) { 'https://example.com/' }

      it 'builds the posts URL at the site root' do
        expect(posts_endpoint).to eq(
          Html2rss::Url.from_absolute('https://example.com/wp/v2/posts?_fields=id%2Ctitle&per_page=100')
        )
      end
    end
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers
