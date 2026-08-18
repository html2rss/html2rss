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
  end

  describe '#parse_response' do
    subject(:parsed) { described_class.new(url:).parse_response(transport_response) }

    let(:transport_response) { instance_double(Faraday::Response, status:, body:) }
    let(:status) { 200 }
    let(:body) { JSON.generate({ 'html' => '<html></html>', 'status_code' => 200 }) }

    it 'returns a ParsedResponse for a scrape envelope' do
      expect(parsed).to be_a(described_class::ParsedResponse)
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
  end
end
