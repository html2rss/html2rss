# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  describe '#articles' do
    subject(:articles) { described_class.new(response, config, request_session:).articles }

    let(:url) { Html2rss::Url.from_absolute('https://example.com/blog') }
    let(:request_session) { instance_double(Html2rss::RequestSession) }
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: File.read(File.expand_path('../../fixtures/auto_source/wordpress_api/index.html', __dir__)),
        headers: { 'content-type' => 'text/html' },
        url:
      )
    end
    let(:api_response) do
      Html2rss::RequestService::Response.new(
        body: File.read(File.expand_path('../../fixtures/auto_source/wordpress_api/posts.json', __dir__)),
        url: Html2rss::Url.from_absolute(
          'https://example.com/wp-json/wp/v2/posts?per_page=100&_fields=id,title,excerpt,content,link,date,categories'
        ),
        headers: { 'content-type' => 'application/json' }
      )
    end
    let(:config) do
      described_class::DEFAULT_CONFIG.merge(
        scraper: {
          wordpress_api: { enabled: true },
          schema: { enabled: false },
          microdata: { enabled: false },
          json_state: { enabled: false },
          semantic_html: { enabled: false },
          html: {
            enabled: false,
            minimum_selector_frequency: described_class::DEFAULT_CONFIG.dig(
              :scraper, :html, :minimum_selector_frequency
            ),
            use_top_selectors: described_class::DEFAULT_CONFIG.dig(:scraper, :html, :use_top_selectors)
          },
          rss_feed_detector: { enabled: false }
        }
      )
    end

    before do
      allow(Parallel).to receive(:flat_map).and_wrap_original do |_original, scrapers, **_kwargs, &block|
        scrapers.flat_map(&block)
      end
      allow(request_session).to receive(:follow_up).and_return(api_response)
    end

    it 'routes the follow-up request through the shared request session' do # rubocop:disable RSpec/ExampleLength
      articles
      expect(request_session).to have_received(:follow_up).with(
        url: api_response.url,
        relation: :auto_source,
        origin_url: url
      )
    end

    it 'returns WordpressApi articles with the mapped attributes' do # rubocop:disable RSpec/ExampleLength
      expected_articles = [
        have_attributes(
          scraper: Html2rss::AutoSource::Scraper::WordpressApi,
          id: '/2024/04/wordpress-api-post/',
          title: 'WordPress API post',
          description: '<p>Full content from the API.</p>',
          url: Html2rss::Url.from_absolute('https://example.com/2024/04/wordpress-api-post/'),
          published_at: DateTime.parse('2024-04-01T12:00:00'),
          categories: match_array(%w[7 9])
        ),
        have_attributes(
          scraper: Html2rss::AutoSource::Scraper::WordpressApi,
          id: '/2024/04/excerpt-only-post/',
          title: 'Excerpt only post',
          description: '<p>Excerpt fallback content.</p>',
          url: Html2rss::Url.from_absolute('https://example.com/2024/04/excerpt-only-post/'),
          published_at: DateTime.parse('2024-04-02T08:15:00'),
          categories: be_empty
        )
      ]

      expect(articles).to match_array(expected_articles)
    end

    it 'aligns WordPress article ids with canonical paths for cross-scraper deduplication' do
      expect(articles.map(&:id)).to eq(['/2024/04/wordpress-api-post/', '/2024/04/excerpt-only-post/'])
    end
  end
end
