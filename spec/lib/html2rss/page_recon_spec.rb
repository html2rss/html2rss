# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::PageRecon do
  let(:html) { File.read('spec/fixtures/local_feed_test.html') }
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  it 'reports alternate feeds, articles_count, and segment stats', :aggregate_failures do
    result = described_class.call(response:, url: 'https://example.com/blog')

    expect(result.final_url).to eq('https://example.com/blog')
    expect(result.html_response).to be(true)
    expect(result.articles_count).to be >= 0
    expect(result.sst).to include(:node_count, :segment_stats)
  end

  it 'assess shares surface and cheap article facts with call', :aggregate_failures do
    assessment = described_class.assess(response:, url: 'https://example.com/blog')
    result = described_class.call(response:, url: 'https://example.com/blog')

    expect(assessment.surface_category).to eq(result.surface_category)
    expect(assessment.articles_count).to eq(result.articles_count)
    expect(assessment.admission_drops).to eq(result.admission_drops)
  end

  it 'surface_category_for matches assess without a second extract job' do
    expect(described_class.surface_category_for(response:, url: 'https://example.com/blog')).to eq(
      described_class.assess(response:, url: 'https://example.com/blog').surface_category
    )
  end

  it 'marks feed responses as unsupported_surface via surface_category_for' do
    feed = Html2rss::RequestService::Response.new(
      body: '<rss version="2.0"><channel></channel></rss>',
      url: Html2rss::Url.from_absolute('https://example.com/feed.xml'),
      headers: { 'content-type' => 'application/rss+xml' },
      status: 200
    )

    expect(described_class.surface_category_for(response: feed, url: feed.url.to_s)).to eq(
      :unsupported_surface
    )
  end

  it 'maps FeedLink alternates without path guessing' do
    body = <<~HTML
      <!DOCTYPE html><html><head>
        <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
      </head><body></body></html>
    HTML
    feed_response = Html2rss::RequestService::Response.new(
      body:,
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )

    result = described_class.call(response: feed_response, url: 'https://example.com/blog')

    expect(result.alternate_feeds).to eq(
      [{ href: 'https://example.com/feed.xml', mime_type: 'application/rss+xml' }]
    )
  end

  it 'probe builds a session, fetches, and returns Probe', :aggregate_failures do
    session = instance_double(Html2rss::RequestSession, fetch_initial_response: response)
    allow(Html2rss::RequestSession).to receive(:build).and_return(session)

    probe = described_class.probe('https://example.com/blog', strategy: :faraday)
    expect(probe).to be_a(described_class::Probe)
    expect(probe.session).to eq(session)
    expect(probe.response).to eq(response)
    expect(probe.strategy).to eq(:faraday)
    expect(probe.result).to be_a(described_class::Result)
  end
end

# rubocop:enable RSpec/ExampleLength
