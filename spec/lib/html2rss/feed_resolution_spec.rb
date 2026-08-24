# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution do
  let(:entry_url) { 'https://example.com/' }
  let(:html) do
    <<~HTML
      <!DOCTYPE html><html><head></head>
      <body><header><a href="/news">News</a></header></body></html>
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
  let(:session) { instance_double(Html2rss::RequestSession) }
  let(:config) do
    instance_double(
      Html2rss::Config,
      auto_source: { entry_resolution: { enabled: true, max_probes: 2 } },
      selectors: nil
    )
  end

  it 'applies a winning listing URL from probes', :aggregate_failures do
    listing = Html2rss::RequestService::Response.new(
      body: <<~HTML,
        <!DOCTYPE html><html><body>
          <article><h2><a href="/news/launch-update">Launch update for spring</a></h2></article>
          <article><h2><a href="/news/api-rollout">API rollout across regions</a></h2></article>
          <article><h2><a href="/news/docs-refresh">Docs refresh for guides</a></h2></article>
        </body></html>
      HTML
      url: Html2rss::Url.from_absolute('https://example.com/news'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
    allow(session).to receive(:follow_up).and_return(listing)

    result = described_class.call(
      entry_url:,
      response:,
      session:,
      config:,
      articles_count: 0,
      surface_category: :high_entropy_surface
    )

    expect(result.applied).to be true
    expect(result.scrape_url).to eq('https://example.com/news')
    expect(result.probe_count).to be >= 1
  end

  it 'skips when policy rejects blocked surfaces' do
    result = described_class.call(
      entry_url:,
      response:,
      session:,
      config:,
      articles_count: 0,
      surface_category: :blocked_surface
    )

    expect(result).to have_attributes(applied: false, reason: :policy_skip)
  end
end

# rubocop:enable RSpec/ExampleLength
