# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession::Pager do
  let(:logger) { instance_double(Logger, warn: nil, debug: nil) }
  let(:session) do
    context = Html2rss::RequestService::Context.new(
      url: 'https://example.com/news',
      policy: Html2rss::RequestService::Policy.new(max_requests: 5),
      budget: Html2rss::RequestService::Budget.new(max_requests: 5)
    )
    Html2rss::RequestSession.new(context:, strategy: :default, logger:)
  end

  describe '.for' do
    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    it 'returns a RelNext pager by default for integer config' do
      pager = described_class.for(3, session:, initial_response:)
      expect(pager).to be_a(Html2rss::RequestSession::Pager::RelNext)
    end

    it 'returns a CustomSelector pager when strategy is custom_selector' do
      pager = described_class.for({ strategy: 'custom_selector', selector: '.next' }, session:, initial_response:)
      expect(pager).to be_a(Html2rss::RequestSession::Pager::CustomSelector)
    end

    it 'raises ArgumentError for unknown strategy' do
      expect { described_class.for({ strategy: 'unknown' }, session:, initial_response:) }
        .to raise_error(ArgumentError, /Unknown pagination strategy/)
    end
  end

  describe '.strategy_names' do
    it 'is the sole source of pagination strategy names for config and schema' do
      expect(described_class.strategy_names).to eq(
        %w[rel_next custom_selector url_template offset json_cursor]
      )
    end
  end

  describe Html2rss::RequestSession::Pager::RelNext do
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :rel_next, max_pages: 2 },
        logger:
      )
    end

    let(:session) do
      context = Html2rss::RequestService::Context.new(
        url: 'https://example.com/news',
        policy: Html2rss::RequestService::Policy.new(max_requests: 3),
        budget: Html2rss::RequestService::Budget.new(max_requests: 3)
      )
      Html2rss::RequestSession.new(context:, strategy: :default, logger:)
    end
    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: <<~HTML,
          <html>
            <head><link rel="next" href="/news?page=2"></head>
            <body><article><h1>page1</h1></article></body>
          </html>
        HTML
        url: Html2rss::Url.from_absolute('https://redirected.example.com/news'),
        headers: { 'content-type' => 'text/html' }
      )
    end
    let(:follow_up_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body><article><h1>page2</h1></article></body></html>',
        url: Html2rss::Url.from_absolute('https://redirected.example.com/news?page=2'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_return(follow_up_response)
    end

    it 'follows rel-next links using the current response url as the follow-up origin', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(pager.to_a).to eq([initial_response, follow_up_response])
      expect(Html2rss::RequestService).to have_received(:execute).with(
        satisfy do |follow_up_context|
          follow_up_context.origin_url.to_s == 'https://redirected.example.com/news' &&
            follow_up_context.url.to_s == 'https://redirected.example.com/news?page=2'
        end,
        strategy: :default
      )
    end

    context 'when the budget is exhausted' do
      let(:error) { Html2rss::RequestService::RequestBudgetExceeded.new('Request budget exhausted') }

      before do
        allow(Html2rss::RequestService).to receive(:execute).and_raise(error)
      end

      it 'stops pagination and logs the stop reason', :aggregate_failures do
        expect(pager.to_a).to eq([initial_response])
        expect(logger).to have_received(:warn).with(
          %r{Html2rss::RequestSession::Pager::RelNext: pagination stopped at https://redirected\.example\.com/news\?page=2 - Request budget exhausted\. Retry with --max-requests 4 or increase request.max_requests in the config\.}
        )
      end
    end
  end

  describe Html2rss::RequestSession::Pager::Base do
    # Hash#fetch returns nil when max_pages is explicitly nil, which would crash
    # effective_page_budget via Integer comparison. Runtime must coerce to DEFAULT.
    context 'when max_pages is explicitly nil' do
      subject(:pager) do
        Html2rss::RequestSession::Pager::RelNext.new(
          session:,
          initial_response:,
          config: { strategy: :rel_next, max_pages: nil },
          logger:
        )
      end

      let(:initial_response) do
        Html2rss::RequestService::Response.new(
          body: '<html><body>page 1</body></html>',
          url: Html2rss::Url.from_absolute('https://example.com/news'),
          headers: { 'content-type' => 'text/html' }
        )
      end

      it 'coerces to DEFAULT_MAX_PAGES without raising' do
        expect(pager.to_a).to eq([initial_response])
      end
    end
  end

  describe Html2rss::RequestSession::Pager::CustomSelector do
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :custom_selector, selector:, max_pages: 2 },
        logger:
      )
    end

    let(:selector) { 'a.next-page' }
    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body><a class="next-page" href="/news?page=2">Next</a></body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }
      )
    end
    let(:follow_up_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>page 2</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news?page=2'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_return(follow_up_response)
    end

    it 'extracts next URL using custom CSS selector' do
      expect(pager.to_a).to eq([initial_response, follow_up_response])
    end

    context 'with an XPath-only selector that at_css rejects' do
      # descendant::a fails Nokogiri LOOKS_LIKE_XPATH / at_css; must fall back to at_xpath.
      let(:selector) { 'descendant::a' }

      it 'extracts next URL via XPath fallback' do
        expect(pager.to_a).to eq([initial_response, follow_up_response])
      end
    end
  end

  describe Html2rss::RequestSession::Pager::UrlTemplate do
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :url_template, param: 'page', max_pages: 3, start_page: 1, step: 1 },
        logger:
      )
    end

    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>page 1</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }
      )
    end
    let(:page2_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>page 2</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news?page=2'),
        headers: { 'content-type' => 'text/html' }
      )
    end
    let(:page3_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>page 3</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news?page=3'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_return(page2_response, page3_response)
    end

    it 'paginates using incrementing page parameter query' do
      expect(pager.to_a).to eq([initial_response, page2_response, page3_response])
    end
  end

  describe Html2rss::RequestSession::Pager::Offset do
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :offset, param: 'offset', max_pages: 2, start_offset: 0, increment: 20 },
        logger:
      )
    end

    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>offset 0</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/api/posts'),
        headers: { 'content-type' => 'text/html' }
      )
    end
    let(:offset20_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>offset 20</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/api/posts?offset=20'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_return(offset20_response)
    end

    it 'paginates using incrementing offset query parameter' do
      expect(pager.to_a).to eq([initial_response, offset20_response])
    end
  end

  describe Html2rss::RequestSession::Pager::JsonCursor do
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :json_cursor, cursor_path: 'meta.next_cursor', param: 'cursor', max_pages: 2 },
        logger:
      )
    end

    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: { meta: { next_cursor: 'abc123token' }, items: [] }.to_json,
        url: Html2rss::Url.from_absolute('https://example.com/api/posts'),
        headers: { 'content-type' => 'application/json' }
      )
    end
    let(:page2_response) do
      Html2rss::RequestService::Response.new(
        body: { meta: { next_cursor: nil }, items: [] }.to_json,
        url: Html2rss::Url.from_absolute('https://example.com/api/posts?cursor=abc123token'),
        headers: { 'content-type' => 'application/json' }
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_return(page2_response)
    end

    it 'digs cursor from JSON response body and appends cursor param' do
      expect(pager.to_a).to eq([initial_response, page2_response])
    end

    context 'with next_url_path relative URL' do
      subject(:pager) do
        described_class.new(
          session:,
          initial_response:,
          config: { strategy: :json_cursor, next_url_path: 'meta.next', max_pages: 2 },
          logger:
        )
      end

      let(:initial_response) do
        Html2rss::RequestService::Response.new(
          body: { meta: { next: '/api/posts?page=2' }, items: [] }.to_json,
          url: Html2rss::Url.from_absolute('https://example.com/api/posts'),
          headers: { 'content-type' => 'application/json' }
        )
      end
      let(:page2_response) do
        Html2rss::RequestService::Response.new(
          body: { meta: { next: nil }, items: [] }.to_json,
          url: Html2rss::Url.from_absolute('https://example.com/api/posts?page=2'),
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'resolves the relative next URL against the response origin' do
        expect(pager.to_a).to eq([initial_response, page2_response])
      end
    end

    context 'with empty next_url_path value' do
      subject(:pager) do
        described_class.new(
          session:,
          initial_response:,
          config: { strategy: :json_cursor, next_url_path: 'meta.next', max_pages: 2 },
          logger:
        )
      end

      let(:initial_response) do
        Html2rss::RequestService::Response.new(
          body: { meta: { next: '' }, items: [] }.to_json,
          url: Html2rss::Url.from_absolute('https://example.com/api/posts'),
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'stops pagination when the next path is empty' do
        expect(pager.to_a).to eq([initial_response])
      end
    end
  end
end
