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

  def run(target = url, options = botasaurus)
    ctx = Html2rss::RequestService::Context.new(url: target, request: { botasaurus: options }, policy:, budget:)
    described_class.new(ctx).execute
  end

  around do |example|
    Html2rss::RequestService.cookie_store = Html2rss::RequestService::CookieStore.new
    ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://localhost:4010') { example.run }
  ensure
    Html2rss::RequestService.cookie_store = nil
  end

  before do
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
      expect(Html2rss::RequestService.cookie_store.fetch(stored_key))
        .to eq('datadome' => 'v2', 'extra' => 'x')
    end
  end

  context 'when the feed config sets a cookie that is also stored' do
    let(:botasaurus) { { cookies: { 'datadome' => 'config' }, execution_mode: 'request' } }
    let(:responses) { [success.call('datadome' => 'v1', 'other' => 'o'), success.call({})] }

    it 'lets the config win and sends cookies in every execution_mode', :aggregate_failures do
      run
      run

      expect(posted.last).to include('execution_mode' => 'request')
      expect(posted.last['cookies']).to eq('datadome' => 'config', 'other' => 'o')
    end
  end

  context 'when a request holding stored cookies is blocked' do
    let(:responses) { [success.call('datadome' => 'stale'), blocked, success.call('datadome' => 'fresh')] }

    it 'evicts the jar and retries once without cookies', :aggregate_failures do
      run
      response = run

      expect(posted.map { |payload| payload['cookies'] }).to eq([nil, { 'datadome' => 'stale' }, nil])
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

  context 'when cookie reuse is logged' do
    let(:responses) { [success.call('datadome' => 'secret-value')] }

    it 'never writes cookie values to the log' do
      allow(Html2rss::Log).to receive(:info)

      run

      expect(Html2rss::Log).to have_received(:info).with(satisfy { |line| !line.include?('secret-value') })
    end
  end

  def stored_key
    Html2rss::RequestService::CookieStore.key(
      host: 'example.com', scraper_base_url: 'http://localhost:4010/', proxy: nil, user_agent: nil
    )
  end
end
