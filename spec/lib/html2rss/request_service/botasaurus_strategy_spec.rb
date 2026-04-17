# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

RSpec.describe Html2rss::RequestService::BotasaurusStrategy do # rubocop:disable RSpec/MultipleMemoizedHelpers
  subject(:execute) { described_class.new(ctx).execute }

  let(:policy) do
    instance_double(
      Html2rss::RequestService::Policy,
      total_timeout_seconds: 30,
      max_decompressed_bytes: 700_000,
      validate_request!: nil
    )
  end
  let(:budget) { instance_double(Html2rss::RequestService::Budget, consume!: nil) }
  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com', policy:, budget:) }
  let(:connection) { instance_double(Faraday::Connection) }
  let(:api_response) do
    instance_double(Faraday::Response, status: 200, body: response_body)
  end
  let(:response_body) do
    {
      url: 'https://redacted.example/technology',
      final_url: 'https://redacted.example/technology/',
      status_code: 200,
      headers: { 'content-type' => 'text/html' },
      html: '<html><body>ok</body></html>',
      error: nil,
      metadata_error: nil,
      request_id: 'request-id',
      attempts: 2,
      strategy_used: 'google_get_bypass',
      render_ms: 5000,
      blocked_detected: false,
      challenge_detected: false,
      error_category: nil
    }.to_json
  end
  let(:captured_post_args) { [] }
  let(:source_fixture_path) { '/Users/gil/versioned/html2rss/botasaurus-scrape-api/reuters_tech.response.json' }
  let(:inline_sample_payload) do
    {
      'url' => 'https://redacted.example/technology',
      'final_url' => 'https://redacted.example/technology/',
      'status_code' => 200,
      'headers' => { 'content-type' => 'text/html' },
      'html' => '<html>redacted</html>',
      'error' => nil,
      'metadata_error' => nil,
      'request_id' => '8d78d630-280c-407f-9884-d71f3c092956',
      'attempts' => 2,
      'strategy_used' => 'google_get_bypass',
      'render_ms' => 8074,
      'blocked_detected' => false,
      'challenge_detected' => false,
      'error_category' => nil
    }
  end
  let(:sample_payload) do
    raw_payload = if File.exist?(source_fixture_path)
                    JSON.parse(File.read(source_fixture_path))
                  else
                    inline_sample_payload
                  end
    raw_payload['url'] = raw_payload['url']&.sub(%r{https?://[^/]+}, 'https://redacted.example')
    raw_payload['final_url'] = raw_payload['final_url']&.sub(%r{https?://[^/]+}, 'https://redacted.example')
    raw_payload
  end

  around do |example|
    ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://localhost:4010') { example.run }
  end

  before do
    allow(Faraday).to receive(:new).and_return(connection)
    allow(connection).to receive(:post) do |path, body, headers|
      captured_post_args << [path, body, headers]
      api_response
    end
  end

  it 'posts with td-like defaults, validates policy, and maps response', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    result = execute

    expect(budget).to have_received(:consume!)
    expect(policy).to have_received(:validate_request!).with(
      url: ctx.url,
      origin_url: ctx.origin_url,
      relation: :initial
    )
    expect(Faraday).to have_received(:new).with(url: 'http://localhost:4010/', request: { timeout: 30 })
    expect(captured_post_args.size).to eq(1)
    path, body, headers = captured_post_args.first
    expect(path).to eq('/scrape')
    expect(headers).to eq('Content-Type' => 'application/json')
    expect(JSON.parse(body)).to include(
      'url' => 'https://example.com/',
      'navigation_mode' => 'auto',
      'max_retries' => 2,
      'headless' => false
    )
    expect(result).to be_a(Html2rss::RequestService::Response)
    expect(result.url.to_s).to eq('https://redacted.example/technology/')
    expect(result.status).to eq(200)
    expect(result.headers.fetch('content-type')).to include('text/html')
    expect(result.body).to include('ok')
  end

  it 'uses status and fallback headers from transport when payload omits them', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    allow(api_response).to receive_messages(status: 202, body: {
      final_url: nil,
      status_code: nil,
      headers: nil,
      html: '<html>fallback</html>'
    }.to_json)

    result = execute

    expect(result.status).to eq(202)
    expect(result.url.to_s).to eq('https://example.com/')
    expect(result.headers).to eq('content-type' => 'text/html')
  end

  it 'raises configuration error when BOTASAURUS_SCRAPER_URL is missing' do # rubocop:disable RSpec/ExampleLength
    ClimateControl.modify(BOTASAURUS_SCRAPER_URL: nil) do
      expect { execute }
        .to raise_error(
          Html2rss::RequestService::BotasaurusConfigurationError,
          /BOTASAURUS_SCRAPER_URL is required/
        )
    end
  end

  it 'raises configuration error when BOTASAURUS_SCRAPER_URL is invalid' do
    ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'not-a-url') do
      expect { execute }
        .to raise_error(Html2rss::RequestService::BotasaurusConfigurationError, /is invalid/)
    end
  end

  it 'maps timeout errors to RequestTimedOut' do
    allow(connection).to receive(:post).and_raise(Faraday::TimeoutError, 'Timed out')

    expect { execute }
      .to raise_error(Html2rss::RequestService::RequestTimedOut, /Timed out/)
  end

  it 'maps network errors to BotasaurusConnectionFailed' do
    allow(connection).to receive(:post).and_raise(Faraday::ConnectionFailed, 'Connection refused')

    expect { execute }
      .to raise_error(Html2rss::RequestService::BotasaurusConnectionFailed, /connection failed/i)
  end

  it 'raises BotasaurusConnectionFailed on invalid JSON payload' do
    allow(api_response).to receive(:body).and_return('not-json')

    expect { execute }
      .to raise_error(Html2rss::RequestService::BotasaurusConnectionFailed, /JSON parse failed/)
  end

  it 'raises BotasaurusConnectionFailed when required html field is missing' do
    allow(api_response).to receive(:body).and_return({ final_url: 'https://redacted.example/path' }.to_json)

    expect { execute }
      .to raise_error(Html2rss::RequestService::BotasaurusConnectionFailed, /missing required 'html'/)
  end

  it 'maps challenge blocks to BlockedSurfaceDetected' do # rubocop:disable RSpec/ExampleLength
    allow(api_response).to receive(:body).and_return({
      html: '<html>challenge</html>',
      error: 'Challenge block detected',
      error_category: 'challenge_block'
    }.to_json)

    expect { execute }
      .to raise_error(Html2rss::RequestService::BlockedSurfaceDetected, /Blocked surface detected/)
  end

  it 'verifies sample contract shape from sanitized fixture', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    fixture = sample_payload
    fixture['html'] = 'x' * 562_671
    allow(api_response).to receive(:body).and_return(JSON.generate(fixture))

    result = execute

    expect(fixture).to include(
      'status_code' => 200,
      'error' => nil,
      'metadata_error' => nil,
      'attempts' => 2,
      'strategy_used' => 'google_get_bypass',
      'blocked_detected' => false,
      'challenge_detected' => false,
      'error_category' => nil
    )
    expect(result.url.to_s).to eq('https://redacted.example/technology/')
    expect(result.headers.fetch('content-type')).to include('text/html')
    expect(result.body.bytesize).to eq(562_671)
  end
end
