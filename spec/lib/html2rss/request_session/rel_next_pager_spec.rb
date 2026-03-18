# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession::RelNextPager do
  subject(:pager) { described_class.new(session:, initial_response:, max_pages: 2, logger:) }

  let(:logger) { instance_double(Logger, warn: nil, debug: nil) }
  let(:session) do
    context = Html2rss::RequestService::Context.new(
      url: 'https://example.com/news',
      policy: Html2rss::RequestService::Policy.new(max_requests: 3),
      budget: Html2rss::RequestService::Budget.new(max_requests: 3)
    )
    Html2rss::RequestSession.new(context:, strategy: :faraday, logger:)
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
      strategy: :faraday
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
        %r{Html2rss::RequestSession::RelNextPager: pagination stopped at https://redirected\.example\.com/news\?page=2 - Request budget exhausted\. Retry with --max-requests 4 or increase top-level max_requests in the config\.}
      )
    end
  end
end
