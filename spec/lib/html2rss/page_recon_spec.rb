# frozen_string_literal: true

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
end
