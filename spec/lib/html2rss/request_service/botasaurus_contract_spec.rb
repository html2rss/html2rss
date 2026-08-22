# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'yaml'

RSpec.describe Html2rss::RequestService::BotasaurusContract do
  let(:url) { Html2rss::Url.from_absolute('https://example.com') }

  describe 'OpenAPI scrape contract' do
    let(:repo_root) { File.expand_path('../../../..', __dir__) }
    let(:openapi_fixture) { File.expand_path('spec/fixtures/botasaurus/openapi.yaml', repo_root) }
    let(:openapi) { YAML.load_file(openapi_fixture) }
    let(:schemas) { openapi.fetch('components').fetch('schemas') }

    it 'is the OpenAPI 2.0 Success/Error contract, not a ScrapeResponse hull', :aggregate_failures do
      expect(openapi.dig('info', 'version')).to eq('2.0.0')
      expect(schemas.keys).not_to include('ScrapeResponse')
    end

    it 'locks request option keys to ScrapeRequest minus url', :aggregate_failures do
      scrape_request = schemas.fetch('ScrapeRequest').fetch('properties')

      expect(scrape_request.keys).not_to include('scroll_to_bottom')
      expect(described_class::REQUEST_OPTION_KEYS.map(&:to_s)).to match_array(scrape_request.keys - %w[url])
    end

    it 'locks execution, navigation, and error closed sets', :aggregate_failures do
      expect(described_class::EXECUTION_MODES).to eq(schemas.fetch('ExecutionMode').fetch('enum'))
      expect(described_class::NAVIGATION_MODES).to eq(schemas.fetch('NavigationMode').fetch('enum'))
      expect(described_class::ERROR_CATEGORIES).to eq(schemas.fetch('ErrorCategory').fetch('enum'))
    end

    it 'locks window_size to required width and height' do
      expect(described_class::WINDOW_SIZE_PROPERTIES.map(&:to_s))
        .to match_array(schemas.fetch('WindowSize').fetch('required'))
    end

    it 'locks wait default and documented clamp without schema min/max', :aggregate_failures do
      wait = schemas.dig('ScrapeRequest', 'properties', 'wait_timeout_seconds')
      clamp = "[#{described_class::MIN_WAIT_TIMEOUT_SECONDS}, #{described_class::MAX_WAIT_TIMEOUT_SECONDS}]"
      expect(described_class::DEFAULT_WAIT_TIMEOUT_SECONDS).to eq(wait.fetch('default'))
      expect(wait.fetch('description')).to include(clamp)
      expect(wait.keys).not_to include('minimum', 'maximum')
    end

    it 'locks max_retries to the OpenAPI maximum' do
      retries = schemas.dig('ScrapeRequest', 'properties', 'max_retries')

      expect(described_class::MAX_RETRIES).to eq(retries.fetch('maximum').to_i)
    end

    it 'locks diagnostics and ChallengeSignal keys', :aggregate_failures do
      expect(described_class::DIAGNOSTICS_KEYS)
        .to match_array(schemas.fetch('ScrapeDiagnostics').fetch('properties').keys)
      expect(described_class::CHALLENGE_KEYS)
        .to match_array(schemas.fetch('ChallengeSignal').fetch('properties').keys)
    end

    it 'keeps html on Success and error fields on Error', :aggregate_failures do
      expect(schemas.dig('ScrapeSuccess', 'properties').keys)
        .to include('html', 'diagnostics', 'metadata_error', 'xhr_responses')
      expect(schemas.dig('ScrapeError', 'properties').keys)
        .to include('error', 'error_category', 'diagnostics')
      expect(schemas.dig('ScrapeError', 'properties').keys).not_to include('html')
    end

    it 'maps scrape HTTP 200 to ScrapeSuccess' do
      expect(openapi.dig('paths', '/scrape', 'post', 'responses', '200', 'content', 'application/json', 'schema'))
        .to eq('$ref' => '#/components/schemas/ScrapeSuccess')
    end

    it 'maps non-200 scrape statuses to ScrapeError' do
      error_ref = { '$ref' => '#/components/schemas/ScrapeError' }
      responses = openapi.dig('paths', '/scrape', 'post', 'responses').except('200').values
      expect(responses).to all(
        include('content' => a_hash_including('application/json' => a_hash_including('schema' => error_ref)))
      )
    end

    it 'stays in sync with the sibling OpenAPI when that repo is checked out' do
      sibling = File.expand_path('../botasaurus-scrape-api/openapi.yaml', repo_root)
      skip "sibling OpenAPI not found at #{sibling}" unless File.exist?(sibling)

      expect(YAML.load_file(openapi_fixture)).to eq(YAML.load_file(sibling))
    end
  end

  describe '::REQUEST_OPTION_KEYS' do
    it 'matches the validator BotasaurusRequestConfig key names' do
      validator_keys = Html2rss::Config::Validator::BotasaurusRequestConfig.key_map.map { |key| key.name.to_sym }

      expect(described_class::REQUEST_OPTION_KEYS).to match_array(validator_keys)
    end
  end

  describe '#request_payload' do
    subject(:payload) { contract.request_payload }

    let(:contract) { described_class.new(url:) }

    it 'sends only the URL so OpenAPI defaults apply', :aggregate_failures do
      expect(payload).to eq(url: 'https://example.com/')
      expect(payload).not_to have_key(:wait_timeout_seconds)
      expect(payload).not_to have_key(:max_retries)
      expect(payload).not_to have_key(:headless)
    end

    context 'when configured wait_timeout_seconds exceeds the work budget cap' do
      let(:contract) { described_class.new(url:, options: { wait_timeout_seconds: 35 }) }

      it 'caps wait_timeout_seconds at MAX_WAIT_TIMEOUT_SECONDS' do
        expect(payload.fetch(:wait_timeout_seconds)).to eq(described_class::MAX_WAIT_TIMEOUT_SECONDS)
      end
    end

    context 'when options include a validator-legal key' do
      let(:contract) { described_class.new(url:, options: { scroll: true }) }

      it 'forwards the key that the validator already accepted' do
        expect(payload[:scroll]).to be true
      end
    end

    context 'when options include window_size' do
      let(:contract) { described_class.new(url:, options: { window_size: { width: 1920, height: 1080 } }) }

      it 'forwards the OpenAPI object shape' do
        expect(payload[:window_size]).to eq(width: 1920, height: 1080)
      end
    end

    context 'when options include an unknown key' do
      let(:contract) do
        described_class.new(url:, options: { scroll_to_bottom: true, lang: 'de' })
      end

      it 'drops the unknown key and keeps OpenAPI keys', :aggregate_failures do
        expect(payload).not_to have_key(:scroll_to_bottom)
        expect(payload[:lang]).to eq('de')
      end
    end
  end

  describe '#parse_response' do
    subject(:parsed) { described_class.new(url:).parse_response(transport_response) }

    let(:transport_response) { instance_double(Faraday::Response, status:, body:) }
    let(:status) { 200 }
    let(:body) do
      JSON.generate(
        {
          'url' => 'https://example.com/',
          'html' => '<html></html>',
          'status_code' => 200,
          'diagnostics' => { 'request_id' => 'req-ok' }
        }
      )
    end

    it 'returns Success for a scrape success envelope' do
      expect(parsed).to be_a(described_class::Success)
    end

    context 'when scrape envelope returns 422 naming window_size' do
      let(:status) { 422 }
      let(:body) do
        JSON.generate(
          {
            'url' => 'https://example.com/',
            'error' => 'window_size.width: Field required',
            'error_category' => 'validation',
            'diagnostics' => { 'request_id' => 'req-422' }
          }
        )
      end

      it 'returns Error naming the field', :aggregate_failures do
        expect(parsed).to be_a(described_class::Error)
        expect(parsed.failure_message).to include('window_size.width')
        expect(parsed.failure_message).to include('req-422')
        expect(parsed.failure_message).to include('error_category=validation')
      end
    end

    context 'when the body is not a scrape envelope' do
      let(:status) { 422 }
      let(:body) do
        JSON.generate(
          {
            'detail' => [
              {
                'loc' => %w[body wait_timeout_seconds],
                'msg' => 'Input should be less than or equal to 30',
                'input' => 35
              }
            ]
          }
        )
      end

      it 'fails loud instead of reading a non-envelope body' do
        expect { parsed }.to raise_error(
          Html2rss::RequestService::BotasaurusServiceError,
          /requires (error|diagnostics|error_category)/
        )
      end
    end

    context 'when success omits html' do
      let(:body) { JSON.generate({ 'url' => 'https://example.com/', 'diagnostics' => { 'request_id' => 'req-1' } }) }

      it 'fails loud because html is required' do
        expect { parsed }.to raise_error(
          Html2rss::RequestService::BotasaurusServiceError,
          /requires html/
        )
      end
    end
  end

  describe 'Success#status' do
    subject(:parsed) { described_class::Success.new(payload:) }

    let(:payload) do
      {
        'html' => '<html>ok</html>',
        'status_code' => 200,
        'diagnostics' => { 'request_id' => 'req-1' }
      }
    end

    [204, 301].each do |document_status|
      context "when status_code is #{document_status}" do
        let(:payload) do
          {
            'html' => '<html>ok</html>',
            'status_code' => document_status,
            'diagnostics' => { 'request_id' => 'req-1' }
          }
        end

        it 'keeps the document status' do
          expect(parsed.status).to eq(document_status)
        end
      end
    end

    context 'when status_code is null' do
      let(:payload) do
        {
          'html' => '<html>ok</html>',
          'status_code' => nil,
          'diagnostics' => { 'request_id' => 'req-1' }
        }
      end

      it 'does not invent a document status' do
        expect(parsed.status).to be_nil
      end
    end
  end

  describe 'Error' do
    subject(:parsed) { described_class::Error.new(payload:, transport_status:) }

    let(:transport_status) { 502 }
    let(:payload) do
      {
        'url' => 'https://example.com/',
        'error' => 'navigation failed',
        'error_category' => 'navigation_error',
        'diagnostics' => { 'request_id' => 'req-502' }
      }
    end

    it 'is not a timeout or challenge block', :aggregate_failures do
      expect(parsed).not_to be_timeout
      expect(parsed).not_to be_challenge_block
    end
  end

  describe 'Error#timeout?' do
    subject(:parsed) { described_class::Error.new(payload:, transport_status:) }

    let(:payload) do
      {
        'error' => 'Scrape timed out after 20 seconds',
        'error_category' => 'timeout',
        'diagnostics' => { 'request_id' => 'req-timeout' }
      }
    end

    context 'when transport is 504' do
      let(:transport_status) { 504 }

      it { is_expected.to be_timeout }
    end

    context 'when error_category is timeout on 502' do
      let(:transport_status) { 502 }

      it { is_expected.to be_timeout }
    end
  end

  describe 'Error#challenge_block?' do
    subject(:parsed) { described_class::Error.new(payload:, transport_status: 502) }

    let(:payload) do
      {
        'error' => 'Challenge block detected',
        'error_category' => 'challenge_block',
        'diagnostics' => {
          'request_id' => 'req-challenge',
          'challenge' => { 'blocked' => true, 'detected' => true, 'marker' => 'Just a moment...' }
        }
      }
    end

    it { is_expected.to be_challenge_block }
  end

  describe 'Success#transport_meta' do
    subject(:parsed) { described_class::Success.new(payload:) }

    let(:payload) do
      {
        'html' => '<html>ok</html>',
        'metadata_error' => 'driver.requests.get failed',
        'diagnostics' => {
          'request_id' => 'req-meta',
          'attempts' => 1,
          'strategy_used' => nil,
          'render_ms' => 154,
          'execution_tier' => 'http_request',
          'challenge' => { 'blocked' => false, 'detected' => false, 'marker' => nil }
        }
      }
    end

    it 'keeps metadata_error as telemetry without treating it as scrape failure', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- html plus nested diagnostics
      expect(parsed.html).to eq('<html>ok</html>')
      expect(parsed.transport_meta).to include(
        'metadata_error' => 'driver.requests.get failed',
        'request_id' => 'req-meta',
        'execution_tier' => 'http_request',
        'challenge' => { 'blocked' => false, 'detected' => false }
      )
    end
  end
end
