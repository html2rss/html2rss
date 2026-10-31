# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

# rubocop:disable-next RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength, RSpec/DescribeMethod
RSpec.describe Html2rss::RequestService::BotasaurusStrategy, 'cookie jar' do
  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      total_timeout_seconds: 30, connect_timeout_seconds: 10, read_timeout_seconds: 30,
      max_decompressed_bytes: 700_000, validate_request!: nil
    )
  end
  let(:budget) do
    instance_double(
      Html2rss::RequestService::Budget,
      consume!: nil, remaining_timeout_seconds: nil, effective_timeout_seconds: 30.0, elapsed_seconds: 0.0
    )
  end
  let(:botasaurus) { {} }
  let(:url) { 'https://example.com' }
  let(:diagnostics) { { request_id: 'req' } }
  let(:success) do
    ->(cookies) { { status: 200, body: { html: '<html>ok</html>', cookies:, diagnostics: }.to_json } }
  end
  let(:blocked) do
    {
      status: 502,
      body: { error: 'blocked', error_category: 'challenge_block', diagnostics: }.to_json
    }
  end
  let(:posted) { [] }

  def run(target = url, options = botasaurus, headers = {})
    ctx = Html2rss::RequestService::Context.new(
      url: target, headers:, request: { botasaurus: options }, policy:, budget:
    )
    described_class.new(ctx).execute
  end

  around do |example|
    Html2rss::RequestService.cookie_store = Html2rss::RequestService::CookieStore.new
    ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://localhost:4010') { example.run }
  ensure
    Html2rss::RequestService.cookie_store = nil
  end

  before do
    stub_const('Html2rss::RequestService::CookieJar::BREAKER', Html2rss::RequestService::ReplayBreaker.new)
    stub_const('Html2rss::RequestService::CookieJar::HOLDOUT_RATE', 0.0)
    stub_request(:post, 'http://localhost:4010/scrape')
      .to_return(*responses.map { |reply| ->(req) { posted << JSON.parse(req.body) and reply } })
  end

  context 'when a scrape earns cookies and the next request replays them' do
    let(:responses) do
      [success.call('datadome' => 'v1'), success.call('datadome' => 'v2', 'extra' => 'x')]
    end

    it 'stores, replays and refreshes merged over the old entry', :aggregate_failures do
      first = run
      run
      run_cookies = posted.map { |payload| payload['cookies'] }

      expect(first.cookies).to eq('datadome' => 'v1')
      expect(run_cookies).to eq([nil, { 'datadome' => 'v1' }])
      expect(posted.map { |payload| payload['execution_mode'] }).to eq([nil, 'request'])
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key))
        .to eq('datadome' => 'v2', 'extra' => 'x')
    end
  end

  context 'when the feed config sets a cookie that is also stored' do
    let(:botasaurus) { { cookies: { 'datadome' => 'config' }, execution_mode: 'request' } }
    let(:responses) { [success.call('datadome' => 'v1', 'other' => 'o'), success.call({})] }

    it 'lets the config win over stored cookies on the replay', :aggregate_failures do
      run
      run

      expect(posted.last).to include('execution_mode' => 'request')
      expect(posted.last['cookies']).to eq('datadome' => 'config', 'other' => 'o')
    end
  end

  context 'when the feed asks for the browser tier explicitly' do
    let(:botasaurus) { { execution_mode: 'browser' } }
    let(:responses) { [success.call('datadome' => 'v1'), success.call({})] }

    it 'never replays stored cookies into it', :aggregate_failures do
      run
      run

      expect(posted.map { |payload| payload['cookies'] }).to eq([nil, nil])
      expect(posted.last).to include('execution_mode' => 'browser')
    end
  end

  context 'when the HTTP-tier replay is blocked in auto mode' do
    let(:responses) { [success.call('datadome' => 'v1'), blocked, success.call('datadome' => 'browser')] }

    it 'falls back to the original mode without cookies', :aggregate_failures do
      run
      run

      expect(posted.last).not_to include('cookies', 'execution_mode')
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key)).to eq('datadome' => 'browser')
    end
  end

  context 'when replays keep being blocked' do
    let(:max) { Html2rss::RequestService::ReplayBreaker::MAX_BLOCKS }
    let(:responses) do
      [success.call('datadome' => 'v')] + Array.new(max) { [blocked, success.call('datadome' => 'v')] }.flatten(1) +
        [success.call({})]
    end

    it 'stops replaying once the breaker trips', :aggregate_failures do
      (max + 2).times { run }

      replayed = posted.map { |payload| payload['cookies'] }
      expect(replayed.count { |cookies| cookies }).to eq(max)
      expect(replayed.last).to be_nil
    end
  end

  context 'when the request falls into the holdout' do
    let(:responses) { [success.call('datadome' => 'v1'), success.call({})] }

    it 'scrapes without cookies', :aggregate_failures do
      stub_const('Html2rss::RequestService::CookieJar::HOLDOUT_RATE', 1.0)
      run
      run

      expect(posted.last).not_to have_key('cookies')
    end
  end

  context 'when a request holding stored cookies is blocked' do
    let(:responses) { [success.call('datadome' => 'stale'), blocked, success.call('datadome' => 'fresh')] }

    it 'evicts the jar and retries once without cookies', :aggregate_failures do
      run
      response = run

      expect(posted.map { |payload| payload['cookies'] }).to eq([nil, { 'datadome' => 'stale' }, nil])
      expect(posted.map { |payload| payload['execution_mode'] }).to eq([nil, 'request', nil])
      expect(response.cookies).to eq('datadome' => 'fresh')
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key)).to eq('datadome' => 'fresh')
    end
  end

  context 'when the retry without cookies is blocked too' do
    let(:responses) { [success.call('datadome' => 'stale'), blocked, blocked] }

    it 'raises after exactly one retry and leaves the jar empty', :aggregate_failures do
      run

      expect { run }.to raise_error(Html2rss::RequestService::BlockedSurfaceDetected)
      expect(posted.size).to eq(3)
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key)).to eq({})
    end
  end

  context 'when a request without stored cookies is blocked' do
    let(:responses) { [blocked] }

    it 'does not retry', :aggregate_failures do
      expect { run }.to raise_error(Html2rss::RequestService::BlockedSurfaceDetected)
      expect(posted.size).to eq(1)
    end
  end

  context 'when a stored-cookie response is a 200 DataDome interstitial' do
    let(:interstitial) do
      { status: 200, body: { html: '<html>captcha-delivery.com DataDome</html>', diagnostics: }.to_json }
    end
    let(:responses) { [success.call('datadome' => 'stale'), interstitial, success.call({})] }

    it 'evicts and retries once without cookies', :aggregate_failures do
      run
      run

      expect(posted.last['cookies']).to be_nil
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key)).to eq({})
    end
  end

  context 'with a different proxy or user agent' do
    let(:responses) { [success.call('datadome' => 'v1'), success.call({}), success.call({}), success.call({})] }

    it 'does not share the jar', :aggregate_failures do
      run
      run(url, { proxy: 'http://proxy.test:8080' })
      run(url, { user_agent: 'Other UA' })
      run('https://other.example')

      expect(posted.drop(1).map { |payload| payload['cookies'] }).to all(be_nil)
    end
  end

  context 'when the retry is blocked too and eviction is observed' do
    let(:responses) { [success.call('datadome' => 'stale'), blocked, blocked] }

    it 'evicts exactly once', :aggregate_failures do
      run
      store = Html2rss::RequestService.cookie_store
      allow(store).to receive(:evict).and_call_original

      expect { run }.to raise_error(Html2rss::RequestService::BlockedSurfaceDetected)
      expect(store).to have_received(:evict).once
    end
  end

  context 'when replaying in auto mode with further botasaurus options' do
    let(:botasaurus) { { execution_mode: 'auto', wait_for_selector: '.item' } }
    let(:responses) { [success.call('datadome' => 'v1'), success.call('datadome' => 'v2')] }
    let(:jars) { [] }

    before do
      allow(Html2rss::RequestService::CookieJar).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap do |jar|
          allow(jar).to receive(:replayable?).and_call_original
          allow(jar).to receive(:replayed).and_call_original
          jars << jar
        end
      end
    end

    it 'overrides only the mode, records the pass with the exact cookies', :aggregate_failures do
      run
      response = run

      expect(response.cookies).to eq('datadome' => 'v2')
      expect(posted.last).to include('execution_mode' => 'request', 'wait_for_selector' => '.item')
      expect(jars.last).to have_received(:replayed).with(:pass, { 'datadome' => 'v1' }).once
      expect(jars.last).not_to have_received(:replayed).with(:block, anything)
    end
  end

  context 'when the replay is blocked in auto mode with further botasaurus options' do
    let(:botasaurus) { { execution_mode: 'auto', wait_for_selector: '.item' } }
    let(:responses) { [success.call('datadome' => 'v1'), blocked, success.call({})] }
    let(:jars) { [] }

    before do
      allow(Html2rss::RequestService::CookieJar).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap do |jar|
          allow(jar).to receive(:replayed).and_call_original
          jars << jar
        end
      end
    end

    it 'records the block and falls back with the original options and no cookies', :aggregate_failures do
      run
      run

      expect(posted[1]).to include('execution_mode' => 'request', 'wait_for_selector' => '.item')
      expect(posted.last).to include('execution_mode' => 'auto', 'wait_for_selector' => '.item')
      expect(posted.last).not_to have_key('cookies')
      expect(jars.last).to have_received(:replayed).with(:block, { 'datadome' => 'v1' }).once
      expect(jars.last).not_to have_received(:replayed).with(:pass, anything)
    end
  end

  context 'when the replay fails with a non-block error' do
    let(:timeout) do
      { status: 504, body: { error: 'slow', error_category: 'timeout', diagnostics: }.to_json }
    end
    let(:responses) { [success.call('datadome' => 'v1'), timeout, success.call({})] }

    it 'propagates it without fallback or block record', :aggregate_failures do
      run

      expect { run }.to raise_error(Html2rss::RequestService::RequestTimedOut)
      expect(posted.size).to eq(2)
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key)).to eq('datadome' => 'v1')
    end
  end

  context 'when the mode is browser' do
    let(:botasaurus) { { execution_mode: 'browser' } }
    let(:jars) { [] }
    let(:responses) { [success.call('datadome' => 'v1'), success.call({})] }

    it 'does not even consult the jar for replayability', :aggregate_failures do
      run
      allow(Html2rss::RequestService::CookieJar).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap { |jar| allow(jar).to receive(:replayable?).and_call_original }
                .tap { |jar| jars << jar }
      end
      run

      expect(jars.last).not_to have_received(:replayable?)
      expect(posted.last).not_to have_key('cookies')
    end
  end

  context 'when the browser mode is a freshly built string' do
    let(:botasaurus) { { execution_mode: 'browser'.dup } }
    let(:responses) { [success.call('datadome' => 'v1'), success.call({})] }

    it 'still never replays', :aggregate_failures do
      run
      run

      expect(posted.last).not_to have_key('cookies')
    end
  end

  context 'when keying the jar by user agent' do
    let(:responses) do
      [success.call('datadome' => 'header'), success.call('datadome' => 'option'), success.call({}), success.call({})]
    end

    it 'uses the botasaurus user_agent, falling back to the User-Agent header', :aggregate_failures do
      run(url, {}, { 'User-Agent' => 'Header UA' })
      run(url, { user_agent: 'Option UA' }, { 'User-Agent' => 'Header UA' })
      run(url, {}, { 'User-Agent' => 'Header UA' })
      run(url, { user_agent: 'Option UA' })

      store = Html2rss::RequestService.cookie_store
      expect(store.fetch(stored_key(user_agent: 'Header UA'))).to eq('datadome' => 'header')
      expect(store.fetch(stored_key(user_agent: 'Option UA'))).to eq('datadome' => 'option')
      expect(posted.last(2).map { |payload| payload['cookies'] })
        .to eq([{ 'datadome' => 'header' }, { 'datadome' => 'option' }])
    end
  end

  context 'when keying the jar by proxy' do
    let(:responses) { [success.call('datadome' => 'p1'), success.call({})] }

    it 'stores and replays under the proxy key only', :aggregate_failures do
      proxy = 'http://proxy.test:8080'
      run(url, { proxy: })
      run(url, { proxy: })

      expect(Html2rss::RequestService.cookie_store.fetch(stored_key(proxy:))).to eq('datadome' => 'p1')
      expect(posted.last['cookies']).to eq('datadome' => 'p1')
    end
  end

  context 'when the strategy builds its jar' do
    let(:responses) { [success.call('datadome' => 'v1')] }

    it 'builds the jar once per strategy and passes the host, scraper url, proxy and UA', :aggregate_failures do
      allow(Html2rss::RequestService::CookieJar).to receive(:new).and_call_original
      ctx = Html2rss::RequestService::Context.new(
        url:, headers: { 'User-Agent' => 'H' }, request: { botasaurus: { proxy: 'http://p:1' } }, policy:, budget:
      )
      described_class.new(ctx).execute

      expect(Html2rss::RequestService::CookieJar).to have_received(:new).once.with(
        host: 'example.com', scraper_base_url: 'http://localhost:4010/', proxy: 'http://p:1', user_agent: 'H'
      )
    end
  end

  context 'when cookie reuse is logged' do
    let(:responses) { [success.call('datadome' => 'secret-value')] }

    it 'never writes cookie values to the log' do
      allow(Html2rss::Log).to receive(:info)

      run

      expect(Html2rss::Log).to have_received(:info).with(satisfy { |line| !line.include?('secret-value') })
    end
  end

  def stored_key(proxy: nil, user_agent: nil)
    Html2rss::RequestService::CookieStore.key(
      host: 'example.com', scraper_base_url: 'http://localhost:4010/', proxy:, user_agent:
    )
  end
end
