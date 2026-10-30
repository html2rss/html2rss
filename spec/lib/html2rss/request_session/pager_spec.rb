# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession::Pager do
  let(:logger) { instance_double(Logger, warn: true, debug: nil) }
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

    context 'when the rel-next link has an empty href' do
      let(:initial_response) do
        Html2rss::RequestService::Response.new(
          body: '<html><head><link rel="next" href=""></head><body>page1</body></html>',
          url: Html2rss::Url.from_absolute('https://example.com/news'),
          headers: { 'content-type' => 'text/html' }
        )
      end

      it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
        expect(pager.to_a).to eq([initial_response])
        expect(Html2rss::RequestService).not_to have_received(:execute)
      end
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
    subject(:pager) { described_class.new(session:, initial_response:, config:, logger:) }

    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html><body>page 1</body></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }
      )
    end
    let(:requested_pages) { [] }
    let(:config) { { max_pages: 3 } }

    before do
      allow(Html2rss::RequestService).to receive(:execute) do |request_context, **|
        Html2rss::RequestService::Response.new(
          body: '<html></html>', url: request_context.url, headers: { 'content-type' => 'text/html' }
        )
      end
    end

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

    it 'raises NotImplementedError from the abstract next_page_url' do
      expect { pager.to_a }.to raise_error(
        NotImplementedError, /Html2rss::RequestSession::Pager::Base#next_page_url must be implemented by subclass/
      )
    end

    it 'returns an enumerator when called without a block', :aggregate_failures do
      allow(pager).to receive(:next_page_url).and_return(nil) # rubocop:disable RSpec/SubjectStub

      expect(pager.each).to be_a(Enumerator)
      expect(pager.each.to_a).to eq([initial_response])
    end

    context 'when next_page_url yields follow-up urls' do
      before do
        allow(pager).to receive(:next_page_url) do |_response, page_number:| # rubocop:disable RSpec/SubjectStub
          requested_pages << page_number
          Html2rss::Url.from_absolute("https://example.com/news?page=#{page_number}")
        end
      end

      it 'requests numbered pages starting at 2 and tags follow-ups as pagination', :aggregate_failures do
        expect(pager.to_a.size).to eq(3)
        expect(requested_pages).to eq([2, 3])
        expect(Html2rss::RequestService).to have_received(:execute).with(
          satisfy { |follow_up_context| follow_up_context.relation == :pagination }, strategy: :default
        ).twice
      end

      context 'when config is an integer page budget' do # rubocop:disable RSpec/NestedGroups
        let(:config) { 2 }

        it 'treats the integer as max_pages' do # rubocop:disable RSpec/MultipleExpectations
          expect(pager.to_a.size).to eq(2)
          expect(requested_pages).to eq([2])
        end
      end

      context 'when max_pages exceeds the session budget' do # rubocop:disable RSpec/NestedGroups
        let(:config) { { max_pages: 10 } }

        it 'clamps the follow-ups to the session budget' do
          pager.to_a
          expect(requested_pages).to eq([2, 3, 4, 5])
        end
      end

      context 'when max_pages is zero' do # rubocop:disable RSpec/NestedGroups
        let(:config) { { max_pages: 0 } }

        it 'falls back to DEFAULT_MAX_PAGES' do
          pager.to_a
          expect(requested_pages).to eq([2, 3, 4, 5])
        end
      end

      context 'when max_pages is not numeric' do # rubocop:disable RSpec/NestedGroups
        let(:config) { { max_pages: 'many' } }

        it 'falls back to DEFAULT_MAX_PAGES' do
          pager.to_a
          expect(requested_pages).to eq([2, 3, 4, 5])
        end
      end

      context 'when max_pages is missing from the config' do # rubocop:disable RSpec/NestedGroups
        let(:config) { {} }

        it 'falls back to DEFAULT_MAX_PAGES' do
          pager.to_a
          expect(requested_pages).to eq([2, 3, 4, 5])
        end
      end

      context 'when the next url was already visited' do # rubocop:disable RSpec/NestedGroups
        before do
          session.remember!(Html2rss::Url.from_absolute('https://example.com/news?page=2'))
        end

        it 'stops without fetching the visited url', :aggregate_failures do
          expect(pager.to_a).to eq([initial_response])
          expect(Html2rss::RequestService).not_to have_received(:execute)
        end
      end

      context 'when next_page_url returns an empty string' do # rubocop:disable RSpec/NestedGroups
        before do
          allow(pager).to receive(:next_page_url).and_return('') # rubocop:disable RSpec/SubjectStub
        end

        it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
          expect(pager.to_a).to eq([initial_response])
          expect(Html2rss::RequestService).not_to have_received(:execute)
        end
      end
    end

    it 'uses DEFAULT_MAX_PAGES when config is omitted' do # rubocop:disable RSpec/ExampleLength
      default_pager = described_class.new(session:, initial_response:, logger:)
      allow(default_pager).to receive(:next_page_url) do |_response, page_number:|
        requested_pages << page_number
        Html2rss::Url.from_absolute("https://example.com/news?page=#{page_number}")
      end

      default_pager.to_a
      expect(requested_pages).to eq([2, 3, 4, 5])
    end

    context 'when the request budget is exhausted without an explicit logger' do
      subject(:pager) { described_class.new(session:, initial_response:, config:) }

      before do
        allow(Html2rss::Log).to receive(:warn)
        allow(Html2rss::RequestService).to receive(:execute)
          .and_raise(Html2rss::RequestService::RequestBudgetExceeded.new('Request budget exhausted'))
        next_url = Html2rss::Url.from_absolute('https://example.com/news?page=2')
        allow(pager).to receive(:next_page_url).and_return(next_url) # rubocop:disable RSpec/SubjectStub
      end

      it 'logs the stop through Html2rss::Log' do # rubocop:disable RSpec/MultipleExpectations
        expect(pager.to_a).to eq([initial_response])
        expect(Html2rss::Log).to have_received(:warn).with(/pagination stopped/)
      end
    end
  end

  describe Html2rss::RequestSession::Pager::CustomSelector do # rubocop:disable RSpec/MultipleMemoizedHelpers
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :custom_selector, selector:, max_pages: 2 },
        logger:
      )
    end

    let(:selector) { 'a.next-page' }
    let(:page_body) { '<html><body><a class="next-page" href="/news?page=2">Next</a></body></html>' }
    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: page_body,
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

    context 'with an XPath-only selector that at_css rejects' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      # descendant::a fails Nokogiri LOOKS_LIKE_XPATH / at_css; must fall back to at_xpath.
      let(:selector) { 'descendant::a' }

      it 'extracts next URL via XPath fallback', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(pager.to_a).to eq([initial_response, follow_up_response])
        expect(Html2rss::RequestService).to have_received(:execute).with(
          satisfy { |request_context|
            request_context.url.to_s == 'https://example.com/news?page=2'
          }, strategy: :default
        )
      end
    end

    context 'when the selector is a valid XPath expression' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:selector) { '//a[@class="next-page"]' }

      it 'requests the XPath match href', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        expect(pager.to_a).to eq([initial_response, follow_up_response])
        expect(Html2rss::RequestService).to have_received(:execute).with(
          satisfy { |request_context|
            request_context.url.to_s == 'https://example.com/news?page=2'
          }, strategy: :default
        )
      end
    end

    context 'when the matched link has no href' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:page_body) { '<html><body><a class="next-page">/news?page=2</a></body></html>' }

      it 'uses the link text as the next URL' do # rubocop:disable RSpec/ExampleLength
        pager.to_a
        expect(Html2rss::RequestService).to have_received(:execute).with(
          satisfy { |request_context|
            request_context.url.to_s == 'https://example.com/news?page=2'
          }, strategy: :default
        )
      end
    end

    context 'when the href has surrounding whitespace' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:page_body) { '<html><body><a class="next-page" href="  /news?page=2  ">Next</a></body></html>' }

      it 'strips the href before requesting it' do # rubocop:disable RSpec/ExampleLength
        pager.to_a
        expect(Html2rss::RequestService).to have_received(:execute).with(
          satisfy { |request_context|
            request_context.url.to_s == 'https://example.com/news?page=2'
          }, strategy: :default
        )
      end
    end

    context 'when the href is blank' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:page_body) { '<html><body><a class="next-page" href="   ">Next</a></body></html>' }

      it 'stops without fetching', :aggregate_failures do
        expect(pager.to_a).to eq([initial_response])
        expect(Html2rss::RequestService).not_to have_received(:execute)
      end
    end

    context 'when the selector matches no node' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:selector) { 'a.missing' }

      it 'stops without fetching', :aggregate_failures do
        expect(pager.to_a).to eq([initial_response])
        expect(Html2rss::RequestService).not_to have_received(:execute)
      end
    end

    context 'when the selector is blank' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:selector) { '' }

      it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
        expect(pager.to_a).to eq([initial_response])
        expect(Html2rss::RequestService).not_to have_received(:execute)
      end
    end

    context 'when the selector is absent from the config' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      subject(:pager) do
        described_class.new(
          session:, initial_response:, config: { strategy: :custom_selector, max_pages: 2 }, logger:
        )
      end

      it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
        expect(pager.to_a).to eq([initial_response])
        expect(Html2rss::RequestService).not_to have_received(:execute)
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

    context 'when recording the requested urls' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:requested_urls) { [] }

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |request_context, **|
          requested_urls << request_context.url.to_s
          Html2rss::RequestService::Response.new(
            body: '<html></html>', url: request_context.url, headers: { 'content-type' => 'text/html' }
          )
        end
      end

      context 'with the default page parameter and step' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(session:, initial_response:, config: { strategy: :url_template, max_pages: 3 }, logger:)
        end

        it 'appends page=N to the query string' do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/news?page=2', 'https://example.com/news?page=3'])
        end
      end

      context 'with a custom parameter, start page, and step' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:,
            config: { strategy: :url_template, param: 'p', start_page: 5, step: 2, max_pages: 3 }, logger:
          )
        end

        it 'computes the target page from start_page and step' do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/news?p=7', 'https://example.com/news?p=9'])
        end
      end

      context 'when the initial url already has a query' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(session:, initial_response:, config: { strategy: :url_template, max_pages: 2 }, logger:)
        end

        let(:initial_response) do
          Html2rss::RequestService::Response.new(
            body: '<html></html>',
            url: Html2rss::Url.from_absolute('https://example.com/news?sort=new'),
            headers: { 'content-type' => 'text/html' }
          )
        end

        it 'keeps existing query parameters' do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/news?page=2&sort=new'])
        end
      end
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

    context 'when recording the requested urls' do
      let(:requested_urls) { [] }

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |request_context, **|
          requested_urls << request_context.url.to_s
          Html2rss::RequestService::Response.new(
            body: '<html></html>', url: request_context.url, headers: { 'content-type' => 'text/html' }
          )
        end
      end

      context 'with the default parameter, start offset, and increment' do # rubocop:disable RSpec/NestedGroups
        subject(:pager) do
          described_class.new(session:, initial_response:, config: { strategy: :offset, max_pages: 3 }, logger:)
        end

        it 'appends offset=N in steps of 20' do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/api/posts?offset=20', 'https://example.com/api/posts?offset=40'])
        end
      end

      context 'with a custom start offset and increment' do # rubocop:disable RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:,
            config: { strategy: :offset, param: 'skip', start_offset: 10, increment: 5, max_pages: 3 }, logger:
          )
        end

        it 'computes the target offset from start_offset and increment' do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/api/posts?skip=15', 'https://example.com/api/posts?skip=20'])
        end
      end
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

    context 'when cursor_path digs the next token' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:requested_urls) { [] }
      let(:body) { { meta: { next_cursor: 'tok' } }.to_json }
      let(:initial_response) do
        Html2rss::RequestService::Response.new(
          body:, url: Html2rss::Url.from_absolute('https://example.com/api/posts'),
          headers: { 'content-type' => 'application/json' }
        )
      end

      before do
        allow(Html2rss::RequestService).to receive(:execute) do |request_context, **|
          requested_urls << request_context.url.to_s
          Html2rss::RequestService::Response.new(
            body: { meta: { next_cursor: nil } }.to_json, url: request_context.url,
            headers: { 'content-type' => 'application/json' }
          )
        end
      end

      context 'with a custom param' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:, config: { strategy: :json_cursor, cursor_path: 'meta.next_cursor',
                                                   param: 'after', max_pages: 2 }, logger:
          )
        end

        it 'appends the token under the custom param', :aggregate_failures do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/api/posts?after=tok'])
        end
      end

      context 'with the default cursor param' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:, config: { strategy: :json_cursor, cursor_path: 'meta.next_cursor',
                                                   max_pages: 2 }, logger:
          )
        end

        it 'appends the token under cursor' do
          pager.to_a
          expect(requested_urls).to eq(['https://example.com/api/posts?cursor=tok'])
        end
      end

      context 'when the token is blank' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:, config: { strategy: :json_cursor, cursor_path: 'meta.next_cursor',
                                                   max_pages: 2 }, logger:
          )
        end

        let(:body) { { meta: { next_cursor: '' } }.to_json }

        it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
          expect(pager.to_a).to eq([initial_response])
          expect(requested_urls).to be_empty
        end
      end

      context 'when the body is not a JSON object' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:, config: { strategy: :json_cursor, cursor_path: 'meta.next_cursor',
                                                   max_pages: 2 }, logger:
          )
        end

        let(:body) { '[1, 2, 3]' }

        it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
          expect(pager.to_a).to eq([initial_response])
          expect(requested_urls).to be_empty
        end
      end

      context 'when the body is invalid JSON' do # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/NestedGroups
        subject(:pager) do
          described_class.new(
            session:, initial_response:, config: { strategy: :json_cursor, cursor_path: 'meta.next_cursor',
                                                   max_pages: 2 }, logger:
          )
        end

        let(:body) { '{not json' }

        it 'stops without fetching' do # rubocop:disable RSpec/MultipleExpectations
          expect(pager.to_a).to eq([initial_response])
          expect(requested_urls).to be_empty
        end
      end
    end
  end
end
