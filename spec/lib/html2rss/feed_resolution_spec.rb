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
      articles: [],
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
      articles: [],
      surface_category: :blocked_surface
    )

    expect(result).to have_attributes(applied: false, reason: :policy_skip)
  end

  describe '.try_apply!' do
    let(:listing_url) { 'https://example.com/news' }
    let(:retry_session) { instance_double(Html2rss::RequestSession) }
    let(:pipeline) { instance_double(Html2rss::FeedPipeline) }
    let(:resources) do
      instance_double(
        Html2rss::FeedPipeline::RuntimePolicy::Resources,
        budget:,
        policy: instance_double(Html2rss::RequestService::Policy)
      )
    end
    let(:budget) { instance_double(Html2rss::RequestService::Budget, remaining_requests: 10) }
    let(:state) { Html2rss::FeedPipeline::AutoFallback::AttemptState.new }
    let(:scrape_target) { Html2rss::ScrapeTarget.from_config(config) }

    before do
      allow(pipeline).to receive_messages(
        request_session_for: retry_session,
        deduplicated_articles: [[], 0, {}]
      )
      allow(retry_session).to receive(:fetch_initial_response).and_return(
        Html2rss::RequestService::Response.new(
          body: '<html></html>',
          url: Html2rss::Url.from_absolute(listing_url),
          headers: { 'content-type' => 'text/html' },
          status: 200
        )
      )
    end

    it 'returns :applied with an updated scrape target when retry yields zero items', :aggregate_failures do
      listing = Html2rss::RequestService::Response.new(
        body: <<~HTML,
          <!DOCTYPE html><html><body>
            <article><h2><a href="/news/a">Alpha launch notes for spring</a></h2></article>
            <article><h2><a href="/news/b">Beta rollout across regions</a></h2></article>
            <article><h2><a href="/news/c">Docs refresh for guides</a></h2></article>
          </body></html>
        HTML
        url: Html2rss::Url.from_absolute(listing_url),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
      allow(session).to receive(:follow_up).and_return(listing)

      outcome = described_class.try_apply!(
        pipeline:, config:, response:, session:, strategy: :faraday, resources:,
        articles: [], scrape_target:, state:, budget:
      )

      expect(outcome).to have_attributes(
        status: :applied,
        scrape_target: have_attributes(entry_url:, effective_url: listing_url)
      )
      expect(state.resolution_tried?).to be(true)
    end

    it 'returns :succeeded when retry extract yields items', :aggregate_failures do
      listing = Html2rss::RequestService::Response.new(
        body: <<~HTML,
          <!DOCTYPE html><html><body>
            <article><h2><a href="/news/a">Alpha launch notes for spring</a></h2></article>
            <article><h2><a href="/news/b">Beta rollout across regions</a></h2></article>
            <article><h2><a href="/news/c">Docs refresh for guides</a></h2></article>
          </body></html>
        HTML
        url: Html2rss::Url.from_absolute(listing_url),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
      article = instance_double(Html2rss::Article)
      allow(session).to receive(:follow_up).and_return(listing)
      allow(pipeline).to receive(:deduplicated_articles).and_return([[article], 0, {}])

      outcome = described_class.try_apply!(
        pipeline:, config:, response:, session:, strategy: :faraday, resources:,
        articles: [], scrape_target:, state:, budget:
      )

      expect(outcome).to have_attributes(status: :succeeded)
      expect(state.result.articles).to eq([article])
      expect(state.result.scrape_target.effective_url).to eq(listing_url)
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
