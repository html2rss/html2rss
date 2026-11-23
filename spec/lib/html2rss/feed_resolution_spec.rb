# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

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
      url: entry_url,
      auto_source: { entry_resolution: { enabled: true, max_probes: 2 } },
      selectors: nil,
      channel: {}
    )
  end
  let(:listing) do
    Html2rss::RequestService::Response.new(
      body: <<~HTML,
        <!DOCTYPE html><html><body>
          <article><h2><a href="/news/launch-update">Launch update for spring</a></h2></article>
          <article><h2><a href="/news/api-rollout">API rollout across regions</a></h2></article>
          <article><h2><a href="/news/docs-refresh">Docs refresh for guides</a></h2></article>
        </body></html>
      HTML
      url: Html2rss::Url.from_absolute('https://example.com/news'),
      headers: { 'content-type' => 'text/html' },
      status: 200,
      transport_meta: { 'error_category' => 'none' }
    )
  end
  let(:resolution) do
    described_class.call(response:, session:, config:, articles: [], slots: 5)
  end

  it 'applies a winning listing URL and hands back the response that won', :aggregate_failures do
    allow(session).to receive(:follow_up).and_return(listing)

    expect(resolution).to have_attributes(applied: true, scrape_url: 'https://example.com/news', reason: :winner)
    expect(resolution.response).to be(listing)
    expect(resolution.probe_count).to be >= 1
  end

  it 'caps the probes by the request slots it may spend', :aggregate_failures do
    allow(session).to receive(:follow_up).and_return(listing)

    described_class.call(response:, session:, config:, articles: [], slots: 1)

    expect(session).to have_received(:follow_up).once
  end

  it 'keeps the configured probe cap when more slots are left', :aggregate_failures do
    allow(session).to receive(:follow_up).and_return(listing)

    resolution

    expect(session).to have_received(:follow_up).at_most(2).times
  end

  it 'runs no tournament without a request slot', :aggregate_failures do
    allow(session).to receive(:follow_up)

    expect(described_class.call(response:, session:, config:, articles: [], slots: 0)).to be_nil
    expect(session).not_to have_received(:follow_up)
  end

  it 'runs no tournament for a feed response' do
    feed = Html2rss::RequestService::Response.new(
      body: '<rss version="2.0"><channel><title>x</title></channel></rss>',
      url: Html2rss::Url.from_absolute('https://example.com/feed.xml'),
      headers: { 'content-type' => 'application/rss+xml' },
      status: 200
    )

    expect(described_class.call(response: feed, session:, config:, articles: [], slots: 5)).to be_nil
  end

  it 'runs no tournament on a blocked surface, deciding the policy once', :aggregate_failures do
    allow(Html2rss::PageRecon).to receive(:surface_category_for).and_return(:blocked_surface)
    allow(Html2rss::FeedResolution::Policy).to receive(:resolve?).and_call_original

    expect(resolution).to be_nil
    expect(Html2rss::PageRecon).to have_received(:surface_category_for).with(response:, url: entry_url)
    expect(Html2rss::FeedResolution::Policy).to have_received(:resolve?).once
  end

  it 'runs no tournament when the entry page is strong enough' do
    articles = Array.new(3) { instance_double(Html2rss::Article, scraper: Html2rss::AutoSource::Scraper::Schema) }
    allow(Html2rss::PageRecon).to receive(:surface_category_for).and_return(:listing)

    expect(described_class.call(response:, session:, config:, articles:, slots: 5)).to be_nil
  end

  it 'raises when articles is not an Array' do
    expect do
      described_class.call(response:, session:, config:, articles: nil, slots: 5)
    end.to raise_error(Html2rss::FeedResolution::InvalidError, 'articles must be an Array')
  end

  it 'rejects an entry URL that is not absolute' do
    relative = instance_double(Html2rss::Config, url: '/news', auto_source: {}, selectors: nil, channel: {})

    expect do
      described_class.call(response:, session:, config: relative, articles: [], slots: 5)
    end.to raise_error(Html2rss::Url::InvalidUrlError, 'URL must be absolute')
  end

  it 'skips without a winner and without a response to reuse', :aggregate_failures do
    empty = Html2rss::RequestService::Response.new(
      body: '<html><body></body></html>', url: Html2rss::Url.from_absolute('https://example.com/news'),
      headers: { 'content-type' => 'text/html' }, status: 200
    )
    allow(session).to receive(:follow_up).and_return(empty)

    expect(resolution).to have_attributes(applied: false, reason: :no_winner, scrape_url: entry_url, response: nil)
  end

  describe '.request_slots_for' do
    it 'is the probe cap when enabled and zero without auto_source', :aggregate_failures do
      expect(described_class.request_slots_for(described_class::DEFAULT_CONFIG.then { { entry_resolution: _1 } }))
        .to eq(described_class::DEFAULT_CONFIG[:max_probes])
      expect(described_class.request_slots_for(nil)).to eq(0)
    end
  end

  it 'is the one owner of the default probe cap' do
    expect(Html2rss::AutoSource::DEFAULT_CONFIG[:entry_resolution]).to be(described_class::DEFAULT_CONFIG)
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
