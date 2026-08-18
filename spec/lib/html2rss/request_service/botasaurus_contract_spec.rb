# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'yaml'

RSpec.describe Html2rss::RequestService::BotasaurusContract do
  let(:url) { Html2rss::Url.from_absolute('https://example.com') }

  describe 'OpenAPI scrape contract' do
    # rubocop:disable RSpec/ExampleLength -- one sibling OpenAPI snapshot assertion
    it 'matches the sibling ScrapeRequest / ScrapeResponse schemas', :aggregate_failures do
      repo_root = File.expand_path('../../../..', __dir__)
      openapi_path = File.expand_path('../botasaurus-scrape-api/openapi.yaml', repo_root)
      skip "sibling OpenAPI not found at #{openapi_path}" unless File.exist?(openapi_path)

      openapi = YAML.load_file(openapi_path)
      schemas = openapi.fetch('components').fetch('schemas')
      scrape_request = schemas.fetch('ScrapeRequest').fetch('properties')
      scrape_response = schemas.fetch('ScrapeResponse').fetch('properties')
      wait = scrape_request.fetch('wait_timeout_seconds')
      retries = scrape_request.fetch('max_retries')
      category = scrape_response.fetch('error_category')
      scrape_responses = openapi.dig('paths', '/scrape', 'post', 'responses')
      clamp_range = "[#{described_class::MIN_WAIT_TIMEOUT_SECONDS}, #{described_class::MAX_WAIT_TIMEOUT_SECONDS}]"

      expect(described_class::REQUEST_OPTION_KEYS.map(&:to_s)).to match_array(scrape_request.keys - %w[url])
      expect(described_class::EXECUTION_MODES).to eq(scrape_request.fetch('execution_mode').fetch('enum'))
      expect(described_class::NAVIGATION_MODES).to eq(scrape_request.fetch('navigation_mode').fetch('enum'))
      expect(described_class::DEFAULT_WAIT_TIMEOUT_SECONDS).to eq(wait.fetch('default'))
      expect(wait.fetch('description')).to include(clamp_range)
      expect(wait).not_to have_key('minimum')
      expect(wait).not_to have_key('maximum')
      expect(described_class::MAX_RETRIES).to eq(retries.fetch('maximum').to_i)
      expect(described_class::ERROR_CATEGORIES).to eq(category.fetch('anyOf').find { _1['enum'] }.fetch('enum'))
      expect(scrape_response.keys).to include(*described_class::META_KEYS)
      expect(scrape_responses.keys).to include('200', '400', '403', '422', '502', '504')
      expect(scrape_responses.except('200').values).to all(
        include('content' => a_hash_including(
          'application/json' => a_hash_including(
            'schema' => { '$ref' => '#/components/schemas/ScrapeResponse' }
          )
        ))
      )
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '::REQUEST_OPTION_KEYS' do
    it 'matches the validator BotasaurusRequestConfig key names' do
      validator_keys = Html2rss::Config::Validator::BotasaurusRequestConfig.key_map.map { |key| key.name.to_sym }

      expect(described_class::REQUEST_OPTION_KEYS).to match_array(validator_keys)
    end
  end

  describe '#request_payload' do
    subject(:payload) { contract.request_payload }

    let(:contract) do
      described_class.new(url:, remaining_timeout_seconds:)
    end
    let(:remaining_timeout_seconds) { 30 }

    it 'sends only the URL so OpenAPI defaults apply', :aggregate_failures do
      expect(payload).to eq(url: 'https://example.com/')
      expect(payload).not_to have_key(:wait_timeout_seconds)
      expect(payload).not_to have_key(:max_retries)
    end

    context 'when remaining budget minus reserve still exceeds the OpenAPI wait default' do
      let(:remaining_timeout_seconds) { 25 }

      it 'does not inflate wait_timeout_seconds above the published default' do
        expect(payload).not_to have_key(:wait_timeout_seconds)
      end
    end

    context 'when remaining budget cannot cover the published wait default' do
      let(:remaining_timeout_seconds) { 12 }

      it 'clamps wait down and disables retries', :aggregate_failures do
        expect(payload.fetch(:wait_timeout_seconds)).to eq(10)
        expect(payload.fetch(:max_retries)).to eq(0)
      end
    end

    context 'when options include a validator-legal key' do
      let(:contract) { described_class.new(url:, options: { scroll: true }) }

      it 'forwards the key that the validator already accepted' do
        expect(payload[:scroll]).to be true
      end
    end

    context 'when options include an unknown key' do
      let(:contract) { described_class.new(url:, options: { not_a_botasaurus_option: true, lang: 'de' }) }

      it 'drops the unknown key and keeps OpenAPI keys', :aggregate_failures do
        expect(payload).not_to have_key(:not_a_botasaurus_option)
        expect(payload[:lang]).to eq('de')
      end
    end
  end

  describe '#parse_response' do
    subject(:parsed) { described_class.new(url:).parse_response(transport_response) }

    let(:transport_response) { instance_double(Faraday::Response, status:, body:) }
    let(:status) { 200 }
    let(:body) { JSON.generate({ 'html' => '<html></html>', 'status_code' => 200 }) }

    it 'returns a ParsedResponse for a scrape envelope' do
      expect(parsed).to be_a(described_class::ParsedResponse)
    end

    context 'when scrape envelope returns 422 naming window_size' do
      let(:status) { 422 }
      let(:body) do
        JSON.generate(
          {
            'url' => 'https://example.com/',
            'html' => '',
            'error' => 'window_size: List should have at least 2 items',
            'error_category' => 'navigation_error',
            'request_id' => 'req-422'
          }
        )
      end

      it 'is an upstream failure that names the field', :aggregate_failures do
        expect(parsed).to be_upstream_failure
        expect(parsed.upstream_failure_message).to include('window_size')
        expect(parsed.upstream_failure_message).to include('req-422')
      end
    end

    context 'when the body is FastAPI HTTPValidationError detail' do
      let(:status) { 422 }
      let(:body) do
        JSON.generate(
          {
            'detail' => [
              {
                'loc' => %w[body wait_timeout_seconds],
                'msg' => 'Input should be less than or equal to 20',
                'input' => 28
              }
            ]
          }
        )
      end

      it 'does not treat FastAPI detail as the scrape envelope', :aggregate_failures do
        expect(parsed).to be_upstream_failure
        expect(parsed.upstream_failure_message).not_to include('wait_timeout_seconds')
        expect(parsed.upstream_failure_message).not_to include('detail=')
      end
    end
  end

  describe 'ParsedResponse#upstream_failure?' do
    subject(:parsed) { described_class::ParsedResponse.new(payload:, transport_status:) }

    let(:transport_status) { 200 }
    let(:payload) do
      {
        'html' => '<html>ok</html>',
        'status_code' => 200,
        'error' => nil
      }
    end

    [204, 301].each do |document_status|
      context "when transport is 200, error is null, and status_code is #{document_status}" do
        let(:payload) do
          {
            'html' => '<html>ok</html>',
            'status_code' => document_status,
            'error' => nil
          }
        end

        it 'is not an upstream failure and keeps the document status', :aggregate_failures do
          expect(parsed).not_to be_upstream_failure
          expect(parsed.status).to eq(document_status)
        end
      end
    end

    context 'when transport is 502' do
      let(:transport_status) { 502 }
      let(:payload) do
        {
          'html' => '<html>error</html>',
          'status_code' => 502,
          'error' => 'navigation failed'
        }
      end

      it { is_expected.to be_upstream_failure }
    end

    context 'when error is present' do
      let(:payload) do
        {
          'html' => '<html>error</html>',
          'status_code' => 200,
          'error' => 'metadata collection failed'
        }
      end

      it { is_expected.to be_upstream_failure }
    end

    context 'when html is omitted on a successful envelope' do
      let(:payload) { { 'url' => 'https://example.com/', 'request_id' => 'req-1', 'error' => nil } }

      it 'uses the OpenAPI empty-string default', :aggregate_failures do
        expect(parsed).not_to be_upstream_failure
        expect(parsed.html).to eq('')
      end
    end
  end

  describe 'ParsedResponse#timeout?' do
    subject(:parsed) { described_class::ParsedResponse.new(payload:, transport_status:) }

    let(:payload) { { 'error' => 'Scrape timed out after 20 seconds', 'error_category' => 'timeout' } }

    context 'when transport is 504' do
      let(:transport_status) { 504 }

      it { is_expected.to be_timeout }
    end

    context 'when error_category is timeout on 502' do
      let(:transport_status) { 502 }

      it { is_expected.to be_timeout }
    end
  end

  describe 'ParsedResponse#challenge_block?' do
    subject(:parsed) { described_class::ParsedResponse.new(payload:, transport_status: 502) }

    let(:payload) do
      {
        'html' => '<html>challenge</html>',
        'error' => 'Challenge block detected',
        'error_category' => 'challenge_block'
      }
    end

    it { is_expected.to be_challenge_block }
  end

  describe 'ParsedResponse#transport_meta' do
    subject(:parsed) { described_class::ParsedResponse.new(payload:, transport_status: 200) }

    let(:payload) do
      {
        'html' => '<html>ok</html>',
        'error' => nil,
        'metadata_error' => 'driver.requests.get failed',
        'request_id' => 'req-meta'
      }
    end

    it 'keeps metadata_error as telemetry without treating it as scrape failure', :aggregate_failures do
      expect(parsed).not_to be_upstream_failure
      expect(parsed.transport_meta).to include(
        'metadata_error' => 'driver.requests.get failed',
        'request_id' => 'req-meta'
      )
    end
  end
end
