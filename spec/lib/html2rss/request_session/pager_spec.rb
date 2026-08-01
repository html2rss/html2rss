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
    Html2rss::RequestSession.new(context:, strategy: :faraday, logger:)
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

  describe Html2rss::RequestSession::Pager::CustomSelector do
    subject(:pager) do
      described_class.new(
        session:,
        initial_response:,
        config: { strategy: :custom_selector, selector: 'a.next-page', max_pages: 2 },
        logger:
      )
    end

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
  end
end
