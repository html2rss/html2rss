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

  it 'keeps one feed slot and listing nav without feed-path starvation', :aggregate_failures do
    urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

    expect(urls.grep(%r{/feed(?:\.xml)?\z|/rss(?:\.xml)?\z})).to eq(['https://example.com/feed.xml'])
    expect(urls).to include('https://example.com/blog').and have_attributes(size: be <= 5)
    expect(urls).not_to include('https://example.com/')
  end

  it 'returns only the feed slot when max is 1' do
    urls = described_class.call(entry_url:, response:, max: 1).map(&:to_s)

    expect(urls).to eq(['https://example.com/feed.xml'])
  end

  it 'uses cluster primary links for listing seeds, not javascript: or mailto:', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <div class="card-item">
          <a href="javascript:void(0)">Share</a>
          <h2><a href="/posts/alpha-release">Alpha release notes for the first card</a></h2>
          <p>Description text for the first clustered card goes here extra.</p>
        </div>
        <div class="card-item">
          <a href="mailto:ed@example.com">Email</a>
          <p><a href="/posts/beta-release">Beta release notes for the second card</a></p>
          <p>Description text for the second clustered card goes here extra.</p>
        </div>
        <div class="card-item">
          <a class="card" href="/posts/gamma-release">Gamma release notes for the third card</a>
          <p>Description text for the third clustered card goes here extra.</p>
        </div>
      </body>
      </html>
    HTML
    response = Html2rss::RequestService::Response.new(
      body: html,
      url: Html2rss::Url.from_absolute(entry_url),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )

    urls = described_class.call(entry_url:, response:, max: 5).map(&:to_s)

    expect(urls).to include(
      'https://example.com/posts/alpha-release',
      'https://example.com/posts/beta-release'
    )
    expect(urls.grep(/javascript:|mailto:/)).to be_empty
  end
end
