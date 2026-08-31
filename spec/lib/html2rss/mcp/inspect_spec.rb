# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers -- response/probe fixtures share across contexts
RSpec.describe Html2rss::MCP::Inspect do
  let(:html) { File.read('spec/fixtures/local_feed_test.html') }
  let(:response_url) { Html2rss::Url.from_absolute('https://example.com/blog') }
  let(:response_status) { 200 }
  let(:response_body) { html }
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: response_body,
      url: response_url,
      headers: { 'content-type' => 'text/html' },
      status: response_status
    )
  end
  let(:probe_strategy) { :faraday }
  let(:probe) do
    Html2rss::PageRecon::Probe.new(
      session: instance_double(Html2rss::RequestSession),
      response:,
      result: Html2rss::PageRecon.call(response:, url: 'https://example.com/blog'),
      strategy: probe_strategy
    )
  end

  before do
    allow(Html2rss::PageRecon).to receive(:probe).and_return(probe)
  end

  it 'reports strategy, scrapers, and SST segment stats', :aggregate_failures do
    result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

    expect(result[:strategy]).to eq(:faraday)
    expect(result[:html_response]).to be(true)
    expect(result[:sst]).to include(:node_count, :segment_stats)
  end

  context 'when Content-Type is octet-stream but the body is HTML' do
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: response_body,
        url: response_url,
        headers: { 'content-type' => 'application/octet-stream' },
        status: response_status
      )
    end

    it 'still reports html_response and runs SST', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

      expect(result[:content_type]).to eq('application/octet-stream')
      expect(result[:html_response]).to be(true)
      expect(result[:sst]).to include(:node_count, :segment_stats)
    end
  end

  context 'when the fetch downgrades https to http' do
    let(:response_url) { Html2rss::Url.from_absolute('http://example.com/blog') }
    let(:response_status) { 301 }

    it 'surfaces final URL, status, and scheme_downgrade from the paid fetch', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

      expect(result[:requested_url]).to eq('https://example.com/blog')
      expect(result[:final_url]).to eq('http://example.com/blog')
      expect(result[:status]).to eq(301)
      expect(result[:scheme_downgrade]).to be(true)
    end
  end

  context 'when the document has a native RSS alternate' do
    let(:response_body) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
        </head>
        <body>
          <a href="/feed">Guessed</a>
        </body>
        </html>
      HTML
    end

    it 'maps FeedLink alternate feeds and does not guess /feed paths', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

      expect(result[:alternate_feeds]).to eq(
        [{ href: 'https://example.com/feed.xml', mime_type: 'application/rss+xml' }]
      )
      expect(result[:alternate_feeds].map { |feed| feed[:href] }).not_to include('/feed')
    end
  end

  it 'builds a request session via PageRecon.probe', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    allow(Html2rss::PageRecon).to receive(:probe).and_call_original
    session = instance_double(Html2rss::RequestSession, fetch_initial_response: response)
    allow(Html2rss::RequestSession).to receive(:build).and_return(session)

    result = Html2rss::PageRecon.probe('https://example.com/blog', strategy: :faraday)
    expect(result.response).to eq(response)
    expect(Html2rss::RequestSession).to have_received(:build)
  end

  it 'reports none_found when no scraper matches' do
    allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(
      Html2rss::AutoSource::Scraper::NoScraperFound.new(category: :unsupported_surface)
    )

    expect(described_class.scraper_info(Nokogiri::HTML::Document.parse(html)))
      .to eq(none_found: 'unsupported_surface')
  end

  it 'reports xhr_capture with query-stripped endpoints for botasaurus', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    captured_response = Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      captured_responses: [
        {
          'url' => 'https://api.example.com/v1/articles?token=secret',
          'body' => '[{"title":"Captured","url":"/a"}]'
        }
      ]
    )
    bot_probe = Html2rss::PageRecon::Probe.new(
      session: instance_double(Html2rss::RequestSession),
      response: captured_response,
      result: Html2rss::PageRecon.call(response: captured_response, url: 'https://example.com/blog'),
      strategy: :botasaurus
    )
    allow(Html2rss::PageRecon).to receive(:probe).and_return(bot_probe)

    result = described_class.call(url: 'https://example.com/blog', strategy: :botasaurus)

    expect(result[:xhr_capture]).to include(
      count: 1,
      candidate_articles: true,
      sample_endpoints: ['https://api.example.com/v1/articles']
    )
    expect(result[:xhr_capture][:sample_endpoints].first).not_to include('token=')
  end

  it 'omits xhr_capture when strategy is not botasaurus' do
    result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

    expect(result).not_to have_key(:xhr_capture)
  end

  it 'returns error for non-HTML parsed bodies' do
    expect(described_class.scraper_info({})).to eq(error: 'Response is not HTML')
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
