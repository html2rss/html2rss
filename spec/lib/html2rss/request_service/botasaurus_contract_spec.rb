# frozen_string_literal: true

require 'spec_helper'

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
end
