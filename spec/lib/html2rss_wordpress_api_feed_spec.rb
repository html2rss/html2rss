# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss do
  describe '.feed with selectors and wordpress api auto-source' do
    subject(:feed) { described_class.feed(config) }

    let(:config) do
      {
        strategy: :faraday,
        channel: { url: 'https://example.com/blog', title: 'Example WordPress Blog' },
        selectors: {
          items: { selector: 'article.post' },
          title: { selector: 'h2 a' },
          link: { selector: 'h2 a', extractor: 'href' }
        },
        auto_source: Html2rss::AutoSource::DEFAULT_CONFIG
      }
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_wrap_original do |_original, context, **_kwargs|
        context.budget.consume!

        case context.url.to_s
        when 'https://example.com/blog'
          Html2rss::RequestService::Response.new(
            body: File.read(File.expand_path('../fixtures/auto_source/wordpress_api/index.html', __dir__)),
            url: context.url,
            headers: { 'content-type' => 'text/html' }
          )
        when 'https://example.com/wp-json/wp/v2/posts?per_page=100&_fields=id,title,excerpt,content,link,date,categories'
          Html2rss::RequestService::Response.new(
            body: File.read(File.expand_path('../fixtures/auto_source/wordpress_api/posts.json', __dir__)),
            url: context.url,
            headers: { 'content-type' => 'application/json' }
          )
        else
          raise "Unexpected URL #{context.url}"
        end
      end
    end

    it 'deduplicates selector and wordpress-api entries for the same canonical post url' do # rubocop:disable RSpec/ExampleLength
      expect(feed.items.map(&:link)).to eq(
        [
          'https://example.com/2024/04/wordpress-api-post/',
          'https://example.com/2024/04/excerpt-only-post/'
        ]
      )
    end

    it 'reserves request budget for the wordpress api follow-up' do
      feed

      expect(Html2rss::RequestService).to have_received(:execute).twice
    end
  end
end
