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
          'https://example.com/wp-json/wp/v2/posts?_fields=id,title,excerpt,content,link,date,categories&per_page=100'
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
          }
        }
      )
    end

    before do
      allow(request_session).to receive(:follow_up).and_return(api_response)
    end

    # Attribute mapping lives in wordpress_api_spec + feed spec; keep session/ids smoke here.
    it 'routes the follow-up request through the shared request session' do # rubocop:disable RSpec/ExampleLength
      articles
      expect(request_session).to have_received(:follow_up).with(
        url: api_response.url,
        relation: :auto_source,
        origin_url: url
      )
    end

    it 'aligns WordPress article ids with canonical paths for cross-scraper deduplication' do
      expect(articles.map(&:id)).to eq(['/2024/04/wordpress-api-post/', '/2024/04/excerpt-only-post/'])
    end
  end
end
