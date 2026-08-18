# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Html2rss::RequestService::BotasaurusContract do
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

  describe '#parse_response' do
    subject(:parsed) { described_class.new(url:).parse_response(transport_response) }

    let(:url) { Html2rss::Url.from_absolute('https://example.com') }
    let(:transport_response) { instance_double(Faraday::Response, status:, body:) }
    let(:status) { 422 }

    context 'when scrape envelope returns 422 naming window_size' do
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

    # main-image compat: :latest still 422s schema errors as FastAPI `detail` until envelope 422 ships.
    context 'when FastAPI returns 422 detail (main-image compat)' do
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
end
