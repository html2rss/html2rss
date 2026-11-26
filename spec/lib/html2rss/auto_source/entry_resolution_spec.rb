# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::EntryResolution do
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

    expect(resolution).to have_attributes(
      applied: true, entry_url:, scrape_url: 'https://example.com/news', reason: :winner
    )
    expect(resolution.response).to be(listing)
    expect(session).to have_received(:follow_up).with(hash_including(url: kind_of(Html2rss::Url))).twice
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
    allow(Html2rss::AutoSource::Assessment).to receive(:surface_category_for).and_return(:blocked_surface)
    allow(Html2rss::AutoSource::EntryResolution::Policy).to receive(:resolve?).and_call_original

    expect(resolution).to be_nil
    expect(Html2rss::AutoSource::Assessment).to have_received(:surface_category_for).with(response:)
    expect(Html2rss::AutoSource::EntryResolution::Policy).to have_received(:resolve?).once
  end

  it 'runs no tournament when the entry page is strong enough' do
    articles = Array.new(3) { instance_double(Html2rss::Article, scraper: Html2rss::AutoSource::Scraper::Schema) }
    allow(Html2rss::AutoSource::Assessment).to receive(:surface_category_for).and_return(:listing)

    expect(described_class.call(response:, session:, config:, articles:, slots: 5)).to be_nil
  end

  it 'raises when articles is not an Array' do
    expect do
      described_class.call(response:, session:, config:, articles: nil, slots: 5)
    end.to raise_error(Html2rss::AutoSource::EntryResolution::InvalidError, 'articles must be an Array')
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

    expect(resolution).to have_attributes(
      applied: false, entry_url:, reason: :no_winner, scrape_url: entry_url, response: nil,
      probe_count: 2, winner_score: nil
    )
  end

  it 'skips a winner that does not beat the articles the entry page already has' do
    articles = Array.new(3) { instance_double(Html2rss::Article, scraper: Html2rss::AutoSource::Scraper::Schema) }
    allow(Html2rss::AutoSource::Assessment).to receive(:surface_category_for).and_return(:app_shell)
    allow(session).to receive(:follow_up).and_return(listing)

    expect(described_class.call(response:, session:, config:, articles:, slots: 5))
      .to have_attributes(applied: false, reason: :no_winner)
  end

  it 'skips when the entry page leaves no candidate to probe', :aggregate_failures do
    allow(Html2rss::AutoSource::EntryResolution::CandidateGenerator).to receive(:call).and_return([])
    allow(session).to receive(:follow_up)

    expect(resolution).to have_attributes(applied: false, reason: :no_candidates, probe_count: 0, scrape_url: entry_url)
    expect(session).not_to have_received(:follow_up)
  end

  it 'reads the vocabulary and the probes from the channel language', :aggregate_failures do
    finnish = instance_double(Html2rss::Config, url: entry_url, auto_source: { entry_resolution: { max_probes: 1 } },
                                                selectors: nil, channel: { language: 'fi' })
    allow(Html2rss::AutoSource::EntryResolution::CandidateGenerator).to receive(:call).and_call_original
    allow(Html2rss::AutoSource::EntryResolution::Probe).to receive(:new).and_call_original
    allow(session).to receive(:follow_up).and_return(listing)

    described_class.call(response:, session:, config: finnish, articles: [], slots: 5)

    expect(Html2rss::AutoSource::EntryResolution::CandidateGenerator).to have_received(:call)
      .with(hash_including(vocabulary: Html2rss::Vocabulary['fi'], max: 1))
    expect(Html2rss::AutoSource::EntryResolution::Probe).to have_received(:new)
      .with(request_session: session, origin_url: Html2rss::Url.from_absolute(entry_url), channel: { language: 'fi' })
  end

  it 'logs the tournament result once for a winner and for a skip', :aggregate_failures do
    allow(Html2rss::Log).to receive(:info)
    allow(session).to receive(:follow_up).and_return(listing)

    resolution
    allow(session).to receive(:follow_up).and_raise(Html2rss::RequestService::ConnectionFailed)
    described_class.call(response:, session:, config:, articles: [], slots: 5)

    expect(Html2rss::Log).to have_received(:info).with(
      a_string_including('"event_name":"entry_resolution.result"', '"host":"example.com"',
                         '"message":"EntryResolution: entry_host=example.com scrape_host=example.com applied=true ' \
                         "probe_count=2 winner_score=#{resolution.winner_score} reason=winner")
    ).once
    expect(Html2rss::Log).to have_received(:info).with(
      a_string_including('applied=false probe_count=0 winner_score=nil reason=no_winner')
    ).once
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
