# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::CandidateGenerator do
  let(:entry_url) { 'https://example.com/' }
  let(:html) do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      </head>
      <body>
        <header><a href="/blog">Blog</a></header>
        <nav><a href="/news">News</a></nav>
        <main>
          <a href="/about">About</a>
        </main>
      </body>
      </html>
    HTML
  end
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute(entry_url),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  it 'returns same-origin feed, nav, and listing path candidates capped at max', :aggregate_failures do
    urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

    expect(urls).to include('https://example.com/feed.xml')
    expect(urls.size).to be <= 5
    expect(urls).not_to include('https://example.com/')
  end
end
