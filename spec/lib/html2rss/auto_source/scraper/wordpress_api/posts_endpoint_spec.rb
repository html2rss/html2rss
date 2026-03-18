# frozen_string_literal: true

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
  let(:page_scope) { instance_double(Html2rss::AutoSource::Scraper::WordpressApi::PageScope, fetchable?: true) }
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

    context 'when the page scope is not safely fetchable' do
      let(:page_scope) { instance_double(Html2rss::AutoSource::Scraper::WordpressApi::PageScope, fetchable?: false) }

      it 'returns nil and logs the unsafe scope', :aggregate_failures do
        expect(posts_endpoint).to be_nil
        expect(logger).to have_received(:warn).with(/unable to derive safe WordPress archive scope/)
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
end
