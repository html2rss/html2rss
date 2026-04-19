# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
RSpec.describe Html2rss::RequestService::BotasaurusStrategy do
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
  let(:request_config) { {} }
  let(:ctx) { Html2rss::RequestService::Context.new(url: 'https://example.com', request: request_config, policy:, budget:) }
  let(:connection) { instance_double(Faraday::Connection) }
  let(:response_status) { 200 }
  let(:response_payload) { base_payload }
  let(:api_response) { instance_double(Faraday::Response, status: response_status, body: JSON.generate(response_payload)) }
  let(:captured_post_args) { [] }
  let(:base_payload) do
    {
      url: 'https://redacted.example/path',
      final_url: 'https://redacted.example/path/',
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
    }
  end
  let(:sanitized_sample_payload) do
    {
      'url' => 'https://redacted.example/path',
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

  describe 'request contract' do
    it 'posts defaults and validates request policy', :aggregate_failures do
      execute

      expect(budget).to have_received(:consume!)
      expect(policy).to have_received(:validate_request!).with(
        url: ctx.url,
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(Faraday).to have_received(:new).with(url: 'http://localhost:4010/', request: { timeout: 30 })
      path, body, headers = captured_post_args.first
      expect(path).to eq('/scrape')
      expect(headers).to eq('Content-Type' => 'application/json')
      expect(JSON.parse(body)).to eq(
        'url' => 'https://example.com/',
        'navigation_mode' => 'auto',
        'max_retries' => 2,
        'headless' => false
      )
    end

    context 'when request includes optional botasaurus fields' do
      let(:request_config) do
        {
          botasaurus: {
            navigation_mode: 'google_get_bypass',
            max_retries: 3,
            wait_for_selector: 'h1',
            wait_timeout_seconds: 15,
            block_images: true,
            block_images_and_css: false,
            wait_for_complete_page_load: true,
            headless: true,
            proxy: 'http://proxy.local:8080',
            user_agent: 'Agent/1.0',
            window_size: [1920, 1080],
            lang: 'en-US',
            ignored_key: 'drop-me'
          }
        }
      end

      it 'forwards allowlisted fields and drops unknown keys', :aggregate_failures do
        execute

        payload = JSON.parse(captured_post_args.first.fetch(1))
        expect(payload).to include(
          'navigation_mode' => 'google_get_bypass',
          'max_retries' => 3,
          'wait_for_selector' => 'h1',
          'wait_timeout_seconds' => 15,
          'block_images' => true,
          'block_images_and_css' => false,
          'wait_for_complete_page_load' => true,
          'headless' => true,
          'proxy' => 'http://proxy.local:8080',
          'user_agent' => 'Agent/1.0',
          'window_size' => [1920, 1080],
          'lang' => 'en-US'
        )
        expect(payload).not_to have_key('ignored_key')
      end
    end
  end

  describe 'response mapping' do
    it 'maps upstream payload to response object', :aggregate_failures do
      result = execute

      expect(result).to be_a(Html2rss::RequestService::Response)
      expect(result.url.to_s).to eq('https://redacted.example/path/')
      expect(result.status).to eq(200)
      expect(result.headers.fetch('content-type')).to include('text/html')
      expect(result.body).to include('ok')
    end

    context 'when response omits headers and url metadata' do
      let(:response_payload) do
        {
          final_url: nil,
          status_code: nil,
          headers: nil,
          html: '<html>fallback</html>',
          error: nil,
          error_category: nil
        }
      end

      it 'falls back to transport status, source url, and default headers', :aggregate_failures do
        result = execute

        expect(result.status).to eq(200)
        expect(result.url.to_s).to eq('https://example.com/')
        expect(result.headers).to eq('content-type' => 'text/html')
      end
    end

    context 'with a deterministic sanitized contract sample' do
      let(:response_payload) do
        sanitized_sample_payload.merge('html' => 'x' * 562_671)
      end

      it 'accepts known sample fields and preserves large rendered body', :aggregate_failures do
        result = execute

        expect(sanitized_sample_payload).to include(
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
  end

  describe 'failure handling' do
    context 'when upstream returns non-200 status with error details' do
      let(:response_status) { 502 }
      let(:response_payload) do
        {
          html: '<html>error</html>',
          status_code: 502,
          error: 'navigation failed',
          error_category: 'navigation_error',
          request_id: 'trace-123'
        }
      end

      it 'raises BotasaurusConnectionFailed with diagnostics' do
        expect { execute }
          .to raise_error(
            Html2rss::RequestService::BotasaurusConnectionFailed,
            /status=502, error_category=navigation_error, error=navigation failed, request_id=trace-123/
          )
      end
    end

    context 'when upstream returns 200 with error payload' do
      let(:response_payload) do
        {
          html: '<html>error</html>',
          status_code: 200,
          error: 'metadata collection failed',
          error_category: 'metadata_error',
          request_id: 'trace-456'
        }
      end

      it 'raises BotasaurusConnectionFailed' do
        expect { execute }
          .to raise_error(
            Html2rss::RequestService::BotasaurusConnectionFailed,
            /status=200, error_category=metadata_error, error=metadata collection failed, request_id=trace-456/
          )
      end
    end

    context 'when upstream payload is invalid JSON' do
      let(:api_response) { instance_double(Faraday::Response, status: 200, body: 'not-json') }

      it 'raises BotasaurusConnectionFailed' do
        expect { execute }
          .to raise_error(Html2rss::RequestService::BotasaurusConnectionFailed, /JSON parse failed/)
      end
    end

    context "when upstream payload omits required 'html'" do
      let(:response_payload) do
        {
          final_url: 'https://redacted.example/path/',
          status_code: 200,
          error: nil,
          error_category: nil
        }
      end

      it 'raises BotasaurusConnectionFailed' do
        expect { execute }
          .to raise_error(Html2rss::RequestService::BotasaurusConnectionFailed, /missing required 'html'/)
      end
    end

    context 'when upstream reports challenge_block' do
      let(:response_payload) do
        {
          html: '<html>challenge</html>',
          error: 'Challenge block detected',
          error_category: 'challenge_block'
        }
      end

      it 'raises BlockedSurfaceDetected' do
        expect { execute }
          .to raise_error(Html2rss::RequestService::BlockedSurfaceDetected, /Blocked surface detected/)
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

    it 'raises configuration error when BOTASAURUS_SCRAPER_URL is missing' do
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
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
