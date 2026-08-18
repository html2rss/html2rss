# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Html2rss::RequestService::BotasaurusContract do
  let(:url) { Html2rss::Url.from_absolute('https://example.com') }

  describe '::MAX_WAIT_TIMEOUT_SECONDS' do
    it 'matches the Botasaurus scrape API wait ceiling' do
      expect(described_class::MAX_WAIT_TIMEOUT_SECONDS).to eq(20)
    end
  end

  describe '.option_keys' do
    it 'matches the validator BotasaurusRequestConfig key names' do
      validator_keys = Html2rss::Config::Validator::BotasaurusRequestConfig.key_map.map { |key| key.name.to_sym }

      expect(described_class.option_keys).to match_array(validator_keys)
    end
  end

  describe '#request_payload' do
    subject(:payload) { contract.request_payload }

    let(:contract) do
      described_class.new(url:, remaining_timeout_seconds:)
    end
    let(:remaining_timeout_seconds) { 30 }

    it 'caps auto-computed remaining-2 wait at the API maximum', :aggregate_failures do
      expect(payload.fetch(:wait_timeout_seconds)).to be <= described_class::MAX_WAIT_TIMEOUT_SECONDS
      expect(payload.fetch(:wait_timeout_seconds)).to eq(20)
    end

    context 'when remaining budget minus reserve still exceeds the API max' do
      let(:remaining_timeout_seconds) { 25 }

      it 'mins remaining-2 with MAX_WAIT_TIMEOUT_SECONDS' do
        expect(payload.fetch(:wait_timeout_seconds)).to eq(20)
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

      it 'drops the unknown key and keeps validator keys', :aggregate_failures do
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

    context 'when FastAPI returns a 422 validation detail' do
      let(:status) { 422 }
      let(:body) do
        JSON.generate(
          {
            'detail' => [
              {
                'loc' => %w[body wait_timeout_seconds],
                'msg' => 'Input should be less than or equal to 20',
                'type' => 'less_than_equal',
                'input' => 28
              }
            ]
          }
        )
      end

      it 'names wait_timeout_seconds and the API cap on BotasaurusServiceError', :aggregate_failures do
        expect(parsed).to be_upstream_failure
        expect(parsed.upstream_failure_message).to include('wait_timeout_seconds')
        expect(parsed.upstream_failure_message).to include('20')
      end
    end

    # main-image compat: :latest still 422s schema errors as FastAPI `detail` until envelope 422 ships.
    context 'when FastAPI returns 422 detail (main-image compat)' do
      let(:status) { 422 }
      let(:body) do
        JSON.generate(
          {
            'detail' => [
              {
                'loc' => %w[body window_size],
                'msg' => 'Input should be a valid list',
                'type' => 'list_type',
                'input' => [1920]
              }
            ]
          }
        )
      end

      it 'appends the field name from detail', :aggregate_failures do
        expect(parsed).to be_upstream_failure
        expect(parsed.upstream_failure_message).to include('window_size')
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
end
