# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'
require 'yaml'

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
  let(:budget) do
    instance_double(
      Html2rss::RequestService::Budget,
      consume!: nil,
      remaining_timeout_seconds: nil,
      effective_timeout_seconds: 30.0,
      elapsed_seconds: 0.0
    )
  end
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
      metadata_error: nil,
      xhr_responses: [],
      diagnostics: {
        request_id: 'request-id',
        attempts: 2,
        strategy_used: 'google_get_bypass',
        render_ms: 5000,
        execution_tier: 'browser_driver',
        challenge: { blocked: false, detected: false, marker: nil }
      }
    }
  end
  let(:sanitized_sample_payload) do
    {
      'url' => 'https://redacted.example/path',
      'final_url' => 'https://redacted.example/technology/',
      'status_code' => 200,
      'headers' => { 'content-type' => 'text/html' },
      'html' => '<html>redacted</html>',
      'metadata_error' => nil,
      'xhr_responses' => [],
      'diagnostics' => {
        'request_id' => '8d78d630-280c-407f-9884-d71f3c092956',
        'attempts' => 2,
        'strategy_used' => 'google_get_bypass',
        'render_ms' => 8074,
        'execution_tier' => 'browser_driver',
        'challenge' => { 'blocked' => false, 'detected' => false, 'marker' => nil }
      }
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
    it 'posts the target URL and validates request policy', :aggregate_failures do
      execute

      expect(budget).to have_received(:consume!)
      expect(policy).to have_received(:validate_request!).with(
        url: ctx.url,
        origin_url: ctx.origin_url,
        relation: :initial
      )
      expect(Faraday).to have_received(:new).with(
        url: 'http://localhost:4010/',
        headers: {
          'User-Agent' => Html2rss::Config::RequestHeaders::DEFAULT_USER_AGENT,
          'Accept' => described_class::TRANSPORT_ACCEPT,
          'Accept-Encoding' => described_class::TRANSPORT_ENCODING
        },
        request: { timeout: 30 }
      )
      path, body, headers = captured_post_args.first
      expect(path).to eq('/scrape')
      expect(headers).to include('Content-Type' => 'application/json')
      expect(headers).to have_key(described_class::REQUEST_ID_HEADER)
      expect(JSON.parse(body)).to eq('url' => 'https://example.com/')
    end

    context 'when request includes optional botasaurus fields and headers' do
      let(:ctx) do
        Html2rss::RequestService::Context.new(
          url: 'https://example.com',
          headers: { 'Accept-Language' => 'en-US,en;q=0.9', 'X-Context-Header' => 'BaseVal' },
          request: request_config,
          policy:,
          budget:
        )
      end
      let(:request_config) do
        {
          botasaurus: {
            execution_mode: 'request',
            navigation_mode: 'google_get_bypass',
            max_retries: 3,
            wait_for_selector: 'h1',
            wait_timeout_seconds: 15,
            scroll: true,
            block_images: true,
            block_images_and_css: false,
            block_trackers: true,
            wait_for_complete_page_load: true,
            headless: true,
            proxy: 'http://proxy.local:8080',
            user_agent: 'Agent/1.0',
            window_size: { width: 1920, height: 1080 },
            lang: 'en-US',
            cookies: { 'session' => 'test-session-token' },
            headers: { 'X-Override' => 'Overridden' },
            ignored_key: 'drop-me'
          }
        }
      end

      it 'forwards allowlisted fields, merged headers, cookies, and drops unknown keys', :aggregate_failures do
        execute

        payload = JSON.parse(captured_post_args.first.fetch(1))
        expect(payload).to include(
          'execution_mode' => 'request',
          'navigation_mode' => 'google_get_bypass',
          'max_retries' => 3,
          'wait_for_selector' => 'h1',
          'wait_timeout_seconds' => 15,
          'scroll' => true,
          'block_images' => true,
          'block_images_and_css' => false,
          'block_trackers' => true,
          'wait_for_complete_page_load' => true,
          'headless' => true,
          'proxy' => 'http://proxy.local:8080',
          'user_agent' => 'Agent/1.0',
          'window_size' => { 'width' => 1920, 'height' => 1080 },
          'lang' => 'en-US',
          'cookies' => { 'session' => 'test-session-token' },
          'headers' => {
            'Accept-Language' => 'en-US,en;q=0.9',
            'X-Context-Header' => 'BaseVal',
            'X-Override' => 'Overridden'
          }
        )
        expect(payload).not_to have_key('ignored_key')
      end
    end

    # rubocop:disable RSpec/NestedGroups -- budget clamp matrix stays with request contract
    context 'when remaining budget is tight' do
      [
        { remaining: 12, max_retries: 0, wait_timeout_seconds: 10 },
        { remaining: 10.5, max_retries: 0, wait_timeout_seconds: 8 },
        { remaining: 20, max_retries: nil, wait_timeout_seconds: nil },
        { remaining: 25, max_retries: nil, wait_timeout_seconds: nil }
      ].each do |example|
        context "with remaining=#{example[:remaining]}" do
          before do
            allow(budget).to receive(:effective_timeout_seconds).and_return(example[:remaining])
          end

          it 'clamps max_retries and wait_timeout_seconds', :aggregate_failures do
            execute

            payload = JSON.parse(captured_post_args.first.fetch(1))
            expect(payload['max_retries']).to eq(example[:max_retries])
            expect(payload['wait_timeout_seconds']).to eq(example[:wait_timeout_seconds])
          end
        end
      end

      context 'when configured wait_timeout_seconds is below the budget cap' do
        let(:request_config) { { botasaurus: { wait_timeout_seconds: 5 } } }

        before { allow(budget).to receive(:effective_timeout_seconds).and_return(20) }

        it 'keeps the lower configured wait timeout' do
          execute

          expect(JSON.parse(captured_post_args.first.fetch(1))['wait_timeout_seconds']).to eq(5)
        end
      end
    end
    # rubocop:enable RSpec/NestedGroups
  end

  describe 'transport headers' do
    let(:repo_root) { File.expand_path('../../../..', __dir__) }
    let(:openapi_fixture) { File.expand_path('spec/fixtures/botasaurus/openapi.yaml', repo_root) }

    it 'sets client headers on Faraday.new', :aggregate_failures do
      execute

      expect(Faraday).to have_received(:new).with(
        hash_including(
          headers: {
            'User-Agent' => Html2rss::Config::RequestHeaders::DEFAULT_USER_AGENT,
            'Accept' => described_class::TRANSPORT_ACCEPT,
            'Accept-Encoding' => described_class::TRANSPORT_ENCODING
          }
        )
      )
    end

    it 'sends Content-Type and X-Request-Id on POST', :aggregate_failures do
      allow(SecureRandom).to receive(:uuid).and_return('stubbed-request-id')

      execute

      _, _, headers = captured_post_args.first
      expect(headers).to eq(
        'Content-Type' => 'application/json',
        described_class::REQUEST_ID_HEADER => 'stubbed-request-id'
      )
    end

    it 'generates a fresh X-Request-Id per strategy instance', :aggregate_failures do
      described_class.new(ctx).execute
      first_id = captured_post_args.first.fetch(2).fetch(described_class::REQUEST_ID_HEADER)

      described_class.new(ctx).execute
      second_id = captured_post_args.last.fetch(2).fetch(described_class::REQUEST_ID_HEADER)

      expect(first_id).not_to eq(second_id)
    end

    it 'forwards ctx.headers only in the JSON body, not on the transport hop', :aggregate_failures do
      ctx_with_headers = Html2rss::RequestService::Context.new(
        url: 'https://example.com',
        headers: { 'Accept-Language' => 'en-US' },
        request: request_config,
        policy:,
        budget:
      )
      described_class.new(ctx_with_headers).execute

      _, body, transport_headers = captured_post_args.first
      expect(transport_headers.keys).not_to include('Accept-Language')
      expect(JSON.parse(body).fetch('headers')).to include('Accept-Language' => 'en-US')
    end

    it 'locks REQUEST_ID_HEADER to OpenAPI POST /scrape header parameter name' do
      openapi = YAML.load_file(openapi_fixture)
      parameters = openapi.dig('paths', '/scrape', 'post', 'parameters') || []
      header_param = parameters.find { |param| param['in'] == 'header' }

      skip 'OpenAPI lacks X-Request-Id header param; sync fixture after scrape-api Phase 1' unless header_param

      expect(described_class::REQUEST_ID_HEADER).to eq(header_param.fetch('name'))
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
      expect(result.captured_responses).to eq([])
      expect(result.transport_meta).to eq(
        'request_id' => 'request-id',
        'strategy_used' => 'google_get_bypass',
        'render_ms' => 5000,
        'attempts' => 2,
        'execution_tier' => 'browser_driver',
        'challenge' => { 'blocked' => false, 'detected' => false }
      )
      expect(result.transport_meta).to be_frozen
    end

    context 'when upstream includes xhr_responses' do
      let(:response_payload) do
        base_payload.merge(
          'xhr_responses' => [
            {
              'url' => 'https://api.example/articles?token=secret',
              'body' => '[{"title":"One","url":"/one"}]',
              'headers' => { 'content-type' => 'application/json' },
              'status_code' => 200
            }
          ]
        )
      end

      it 'maps xhr_responses onto Response#captured_responses', :aggregate_failures do
        result = execute

        expect(result.captured_responses).to contain_exactly(
          a_hash_including(
            'url' => 'https://api.example/articles?token=secret',
            'body' => '[{"title":"One","url":"/one"}]',
            'status_code' => 200
          )
        )
      end
    end

    context 'when xhr_responses exceed the aggregate size cap' do
      let(:chunk) { 'y' * Html2rss::RequestService::BotasaurusContract::Success::MAX_XHR_BODY_BYTES }
      let(:response_payload) do
        base_payload.merge(
          'xhr_responses' => Array.new(5) do |index|
            { 'url' => "https://api.example/#{index}", 'body' => chunk, 'status_code' => 200 }
          end
        )
      end

      it 'drops overflow after the aggregate byte budget is exhausted', :aggregate_failures do
        result = execute

        expect(result.captured_responses.size).to eq(4)
        expect(result.captured_responses.map { _1.fetch('url') }).to eq(
          %w[https://api.example/0 https://api.example/1 https://api.example/2 https://api.example/3]
        )
      end
    end

    context 'when an individual xhr body exceeds the per-body size cap' do
      let(:oversized_body) { 'x' * (Html2rss::RequestService::BotasaurusContract::Success::MAX_XHR_BODY_BYTES + 1) }
      let(:response_payload) do
        base_payload.merge(
          'xhr_responses' => [
            { 'url' => 'https://api.example/a', 'body' => '{"ok":true}', 'status_code' => 200 },
            { 'url' => 'https://api.example/b', 'body' => oversized_body, 'status_code' => 200 }
          ]
        )
      end

      it 'drops oversize bodies and keeps in-budget captures', :aggregate_failures do
        result = execute

        expect(result.captured_responses.size).to eq(1)
        expect(result.captured_responses.first.fetch('url')).to eq('https://api.example/a')
      end
    end

    [204, 301].each do |document_status|
      context "when scrape envelope succeeds with document status_code #{document_status}" do
        let(:response_payload) { base_payload.merge(status_code: document_status) }

        it 'does not raise and maps Response#status from the document code', :aggregate_failures do
          result = execute

          expect(result.status).to eq(document_status)
          expect(result.body).to include('ok')
        end
      end
    end

    context 'when response omits headers and url metadata' do
      let(:response_payload) do
        {
          url: 'https://example.com/',
          final_url: nil,
          status_code: nil,
          headers: nil,
          html: '<html>fallback</html>',
          diagnostics: { request_id: 'req-fallback' }
        }
      end

      it 'keeps a nil document status, source url, and empty headers', :aggregate_failures do
        result = execute

        expect(result.status).to be_nil
        expect(result.url.to_s).to eq('https://example.com/')
        expect(result.headers).to eq({})
        expect(result.captured_responses).to eq([])
        expect(result.transport_meta).to include('request_id' => 'req-fallback')
      end
    end

    context 'with a deterministic sanitized contract sample' do
      let(:response_payload) do
        sanitized_sample_payload.merge('html' => 'x' * 562_671)
      end

      it 'preserves large rendered body and final URL from the sample envelope', :aggregate_failures do
        result = execute

        expect(result.url.to_s).to eq('https://redacted.example/technology/')
        expect(result.headers.fetch('content-type')).to include('text/html')
        expect(result.body.bytesize).to eq(562_671)
      end
    end
  end

  describe 'failure handling' do
    context 'when scrape envelope returns 422 naming window_size' do
      let(:response_status) { 422 }
      let(:response_payload) do
        {
          url: 'https://example.com/',
          error: 'window_size.width: Field required',
          error_category: 'validation',
          diagnostics: { request_id: 'req-422' }
        }
      end

      it 'raises BotasaurusServiceError naming window_size' do
        expect { execute }
          .to raise_error(
            Html2rss::RequestService::BotasaurusServiceError,
            /window_size/
          )
      end
    end

    context 'when scrape envelope returns 504 timeout' do
      let(:response_status) { 504 }
      let(:response_payload) do
        {
          url: 'https://example.com/',
          error: 'Scrape timed out after 20 seconds',
          error_category: 'timeout',
          diagnostics: { request_id: 'req-504' }
        }
      end

      it 'raises RequestTimedOut with envelope diagnostics' do
        expect { execute }
          .to raise_error(
            Html2rss::RequestService::RequestTimedOut,
            /error_category=timeout.*req-504/
          )
      end
    end

    context 'when upstream returns non-200 status with error details' do
      let(:response_status) { 502 }
      let(:response_payload) do
        {
          url: 'https://example.com/',
          error: 'navigation failed',
          error_category: 'navigation_error',
          diagnostics: { request_id: 'trace-123' }
        }
      end

      it 'raises BotasaurusServiceError with diagnostics' do
        expect { execute }
          .to raise_error(
            Html2rss::RequestService::BotasaurusServiceError,
            /status=502, error_category=navigation_error, error=navigation failed, request_id=trace-123/
          )
      end
    end

    context 'when success includes metadata_error' do
      let(:response_payload) do
        base_payload.merge(metadata_error: 'metadata collection failed')
      end

      it 'keeps HTML success and records metadata_error as telemetry', :aggregate_failures do
        result = execute

        expect(result.body).to include('ok')
        expect(result.transport_meta).to include('metadata_error' => 'metadata collection failed')
      end
    end

    context 'when upstream payload is invalid JSON' do
      let(:api_response) { instance_double(Faraday::Response, status: 200, body: 'not-json') }

      it 'raises BotasaurusServiceError' do
        expect { execute }
          .to raise_error(Html2rss::RequestService::BotasaurusServiceError, /JSON parse failed/)
      end
    end

    context 'when the scrape envelope omits html on success' do
      let(:response_payload) do
        {
          url: 'https://example.com/',
          final_url: 'https://redacted.example/path/',
          status_code: 200,
          diagnostics: { request_id: 'req-missing-html' }
        }
      end

      it 'raises because html is required' do
        expect { execute }
          .to raise_error(Html2rss::RequestService::BotasaurusServiceError, /requires html/)
      end
    end

    context 'when upstream reports challenge_block' do
      let(:response_status) { 502 }
      let(:response_payload) do
        {
          url: 'https://example.com/',
          error: 'Challenge block detected',
          error_category: 'challenge_block',
          diagnostics: {
            request_id: 'req-challenge',
            challenge: { blocked: true, detected: true, marker: 'Just a moment...' }
          }
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
