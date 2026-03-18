# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource::Scraper::WordpressApi do
  subject(:articles) { described_class.new(parsed_body, url:, request_session:).each.to_a }

  let(:url) { Html2rss::Url.from_absolute('https://example.com/blog') }
  let(:request_session) { instance_double(Html2rss::RequestSession) }
  let(:fixture_root) { File.expand_path('../../../../fixtures/auto_source/wordpress_api', __dir__) }
  let(:index_html) { File.read(File.join(fixture_root, 'index.html')) }
  let(:parsed_body) { Nokogiri::HTML(index_html) }

  before do
    allow(request_session).to receive(:follow_up)
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
      allow(request_session).to receive(:follow_up).and_return(api_response)
      allow(Html2rss::Log).to receive(:warn)
    end

    it 'returns no articles and logs a warning', :aggregate_failures do
      expect(articles).to eq([])
      expect(Html2rss::Log).to have_received(:warn).with(/unsupported WordPress API posts content type/i)
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

# rubocop:enable RSpec/MultipleMemoizedHelpers
