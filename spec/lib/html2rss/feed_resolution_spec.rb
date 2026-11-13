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

  it 'raises when articles is not an Array' do
    expect do
      described_class.call(
        entry_url:,
        response:,
        session:,
        config:,
        articles: nil,
        surface_category: :listing
      )
    end.to raise_error(Html2rss::FeedResolution::InvalidError, 'articles must be an Array')
  end

  it 'rejects a truthy non-array on the runner' do
    expect do
      described_class::Runner.new(entry_url:, response:, session:, config:, articles: 'no')
    end.to raise_error(Html2rss::FeedResolution::InvalidError, 'articles must be an Array')
  end

  it 'rejects a runner entry URL that is not absolute' do
    expect do
      described_class::Runner.new(entry_url: '/news', response:, session:, config:, articles: [])
    end.to raise_error(Html2rss::Url::InvalidUrlError, 'URL must be absolute')
  end

  it 'allows omitting the runner surface category' do
    runner = described_class::Runner.new(entry_url:, response:, session:, config:, articles: [])

    expect(runner).to be_a(described_class::Runner)
  end

  it 'accepts an Array subclass and keeps the absolute entry URL' do
    runner = described_class::Runner.new(
      entry_url:, response:, session:, config:, articles: Class.new(Array).new, surface_category: :blocked_surface
    )

    expect(runner.call).to have_attributes(applied: false, reason: :policy_skip, scrape_url: entry_url)
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
    let(:active_budget) { budget }
    let(:one_article_extraction) do
      Html2rss::FeedPipeline::Extraction.new(
        articles: [instance_double(Html2rss::Article)], dedup_dropped: 0, admission_drops: {}, feed_channel: nil
      )
    end
    let(:state) { Html2rss::FeedPipeline::AutoFallback::AttemptState.new }
    let(:scrape_target) { Html2rss::ScrapeTarget.from_config(config) }
    let(:applied_resolution) do
      described_class::Result.new(
        entry_url:, scrape_url: listing_url, applied: true, reason: :winner, probe_count: 1, winner_score: 1
      )
    end
    let(:skipped_resolution) do
      described_class::Result.new(
        entry_url:, scrape_url: entry_url, applied: false, reason: :no_winner, probe_count: 0, winner_score: nil
      )
    end
    let(:apply_outcome) do
      described_class.try_apply!(
        pipeline:, config:, response:, session:, strategy: :default, resources:,
        articles: [], scrape_target:, state:, budget: active_budget
      )
    end

    before do
      allow(pipeline).to receive_messages(
        request_session_for: retry_session,
        extract: Html2rss::FeedPipeline::Extraction.new(
          articles: [], dedup_dropped: 0, admission_drops: {}, feed_channel: nil
        )
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

    it 'returns nil and keeps entry scrape target when retry yields zero items', :aggregate_failures do
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
        pipeline:, config:, response:, session:, strategy: :default, resources:,
        articles: [], scrape_target:, state:, budget:
      )

      expect(outcome).to be_nil
      expect(scrape_target).to have_attributes(entry_url:, effective_url: entry_url)
      expect(state.resolution_tried?).to be(true)
      expect(state.entry_resolution).to have_attributes(applied: true, reason: :winner)
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
      feed_channel = Html2rss::Syndication::ChannelFacts.new(author: 'Listing Feed Author')
      allow(session).to receive(:follow_up).and_return(listing)
      allow(pipeline).to receive(:extract)
        .and_return(Html2rss::FeedPipeline::Extraction.new(
                      articles: [article], dedup_dropped: 1, admission_drops: { 'sponsored' => 2 }, feed_channel:
                    ))

      outcome = described_class.try_apply!(
        pipeline:, config:, response:, session:, strategy: :default, resources:,
        articles: [], scrape_target:, state:, budget:
      )

      expect(outcome).to have_attributes(status: :succeeded)
      expect(outcome.scrape_target.effective_url).to eq(listing_url)
      expect(state.result.articles).to eq([article])
      expect(state.result).to have_attributes(feed_channel:, dedup_dropped: 1, admission_drops: { 'sponsored' => 2 })
      expect(state.result.scrape_target.effective_url).to eq(listing_url)
    end

    it 'extracts the resolved page through a session for it and records that hop', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      retry_response = retry_session.fetch_initial_response
      allow(session).to receive(:follow_up).and_return(retry_response)
      allow(Html2rss::PageRecon).to receive(:assess).and_return(
        Html2rss::PageRecon::Assessment.new(surface_category: :listing, articles_count: 0, admission_drops: {},
                                            html_response: true)
      )
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(pipeline).to receive(:extract).and_return(one_article_extraction)

      apply_outcome

      expect(pipeline).to have_received(:request_session_for)
        .with(config, strategy: :default, resources:, scrape_url: listing_url)
      expect(pipeline).to have_received(:extract).with(config:, response: retry_response,
                                                       request_session: retry_session)
      expect(state.attempts).to eq([{ strategy: :default, items_count: 1, error_class: nil }])
      expect(state.result).to have_attributes(response: retry_response, selected_strategy: :default, attempt_count: 1,
                                              entry_resolution: state.entry_resolution)
      expect(state.entry_resolution).to have_attributes(applied: true)
    end

    it 're-raises non-fallback errors from the retry' do
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(retry_session).to receive(:fetch_initial_response).and_raise(Html2rss::RequestService::InvalidUrl)

      expect { apply_outcome }.to raise_error(Html2rss::RequestService::InvalidUrl)
    end

    it 'returns nil when the retry raises a generic error', :aggregate_failures do
      log = StringIO.new
      Html2rss.logger = Logger.new(log)
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(retry_session).to receive(:fetch_initial_response).and_raise(Html2rss::Error)

      expect(apply_outcome).to be_nil
      expect(log.string).to include('feed_resolution.retry_failed', 'Html2rss::Error')
    ensure
      Html2rss.reset_defaults!
    end

    it 'returns nil when the retry exceeds the request budget', :aggregate_failures do
      log = StringIO.new
      Html2rss.logger = Logger.new(log)
      allow(described_class).to receive(:call).and_return(applied_resolution)
      error = Html2rss::RequestService::RequestBudgetExceeded
      allow(retry_session).to receive(:fetch_initial_response).and_raise(error)

      expect(apply_outcome).to be_nil
      expect(log.string).to include('feed_resolution.budget_exhausted')
    ensure
      Html2rss.reset_defaults!
    end

    it 'returns nil when policy rejects after the page is assessed', :aggregate_failures do
      articles = Array.new(3) { instance_double(Html2rss::Article, scraper: Html2rss::AutoSource::Scraper::Schema) }
      assessment = Html2rss::PageRecon::Assessment.new(
        surface_category: :listing, articles_count: 3, admission_drops: {}, html_response: true
      )
      allow(Html2rss::PageRecon).to receive(:assess).and_return(assessment)
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(pipeline).to receive(:extract).and_return(one_article_extraction)

      outcome = described_class.try_apply!(
        pipeline:, config:, response:, session:, strategy: :default, resources:,
        articles:, scrape_target:, state:, budget:
      )

      expect(Html2rss::PageRecon).to have_received(:assess).with(response:, url: entry_url)
      expect(outcome).to be_nil
    end

    it 'returns nil when resolution already ran' do
      state.mark_resolution_tried!
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(pipeline).to receive(:extract).and_return(one_article_extraction)

      expect(apply_outcome).to be_nil
    end

    it 'returns nil for a feed response' do
      feed = instance_double(Html2rss::RequestService::Response, feed_response?: true)
      assessment = Html2rss::PageRecon::Assessment.new(
        surface_category: :listing, articles_count: 0, admission_drops: {}, html_response: false
      )
      allow(Html2rss::PageRecon).to receive(:assess).and_return(assessment)
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(pipeline).to receive(:extract).and_return(one_article_extraction)

      outcome = described_class.try_apply!(
        pipeline:, config:, response: feed, session:, strategy: :default, resources:,
        articles: [], scrape_target:, state:, budget:
      )

      expect(outcome).to be_nil
    end

    it 'does not succeed when the tournament does not apply' do
      allow(described_class).to receive(:call).and_return(skipped_resolution)
      allow(pipeline).to receive(:extract).and_return(one_article_extraction)

      expect(apply_outcome).to be_nil
    end

    it 'returns nil when fewer than three requests remain' do
      low_budget = instance_double(Html2rss::RequestService::Budget, remaining_requests: 2)
      allow(described_class).to receive(:call).and_return(applied_resolution)
      allow(pipeline).to receive(:extract).and_return(one_article_extraction)

      outcome = described_class.try_apply!(
        pipeline:, config:, response:, session:, strategy: :default, resources:,
        articles: [], scrape_target:, state:, budget: low_budget
      )

      expect(outcome).to be_nil
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
