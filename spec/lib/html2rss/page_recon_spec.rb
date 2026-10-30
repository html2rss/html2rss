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

  let(:item_count) { 7 }
  let(:list_items) do
    (1..item_count).map do |index|
      '<li class="post"><h2>' \
        "<a href=\"/posts/#{index}\">Post title number #{index} with words</a></h2>" \
        "<p>Description text for post #{index} is long enough to count as content here.</p></li>"
    end.join
  end
  let(:list_response) do
    Html2rss::RequestService::Response.new(
      body: '<!DOCTYPE html><html><head><title>Blog</title></head>' \
            "<body><main><ul>#{list_items}</ul></main></body></html>",
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

  it 'reports exact segment stats for a multi-item list page', :aggregate_failures do
    result = described_class.call(response: list_response, url: 'https://example.com/blog')

    expect(result.segment_stats).to eq(
      found: 7,
      strategies: [:list],
      sample_paths: Array.new(5, '/html/body/main/ul/li')
    )
    expect(result.sst).to include(
      node_count: be_a(Integer).and(be_positive),
      degraded: false,
      segment_stats: result.segment_stats
    )
  end

  it 'omits sst and segment stats when the body normalizes to no document', :aggregate_failures do
    empty = Html2rss::RequestService::Response.new(
      body: '',
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
    result = described_class.call(response: empty, url: 'https://example.com/blog')

    expect(result.sst).to be_nil
    expect(result.segment_stats).to be_nil
  end

  context 'with more list items than the cheap article limit' do
    let(:item_count) { 12 }

    it 'caps the cheap article count at the fixed AutoSource limit', :aggregate_failures do
      assessment = described_class.assess(response: list_response, url: 'https://example.com/blog')

      expect(assessment.articles_count).to eq(10)
      expect(assessment.html_response).to be(true)
    end
  end

  it 'reports no cheap articles or drops for a non-HTML, non-feed body', :aggregate_failures do
    plain = Html2rss::RequestService::Response.new(
      body: 'plain text body',
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/plain' },
      status: 200
    )
    assessment = described_class.assess(response: plain, url: 'https://example.com/blog')

    expect(assessment.articles_count).to eq(0)
    expect(assessment.admission_drops).to eq({})
  end

  it 'reports found zero when the page has no list segments' do
    response = Html2rss::RequestService::Response.new(
      body: '<html><body><p>Just a paragraph.</p></body></html>',
      url: Html2rss::Url.from_absolute('https://example.com/blog'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )

    expect(described_class.call(response:, url: 'https://example.com/blog').segment_stats).to eq(found: 0)
  end

  it 'skips sst and segment stats for non-HTML responses', :aggregate_failures do
    feed = Html2rss::RequestService::Response.new(
      body: '<rss version="2.0"><channel></channel></rss>',
      url: Html2rss::Url.from_absolute('https://example.com/feed.xml'),
      headers: { 'content-type' => 'application/rss+xml' },
      status: 200
    )
    result = described_class.call(response: feed, url: feed.url.to_s)

    expect(result.sst).to be_nil
    expect(result.segment_stats).to be_nil
  end

  it 'probe builds a session, fetches, and returns Probe', :aggregate_failures do
    session = instance_double(Html2rss::RequestSession, fetch_initial_response: response)
    allow(Html2rss::RequestSession).to receive(:build).and_return(session)

    probe = described_class.probe('https://example.com/blog', strategy: :default)
    expect(probe).to be_a(described_class::Probe)
    expect(probe.session).to eq(session)
    expect(probe.response).to eq(response)
    expect(probe.strategy).to eq(:default)
    expect(probe.result).to be_a(described_class::Result)
  end
end

# rubocop:enable RSpec/ExampleLength
