# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::DeterministicHttpStatus do
  let(:url) { Html2rss::Url.from_absolute('https://example.com/missing') }

  let(:response_with) do
    ->(status) { Html2rss::RequestService::Response.new(body: '', url:, headers: {}, status:) }
  end

  describe '.check!' do
    # rubocop:disable-next RSpec/ExampleLength -- one raise payload per status
    it 'raises for every deterministic status with status and url', :aggregate_failures do
      described_class::STATUSES.each do |status|
        expect { described_class.check!(response_with.call(status)) }.to raise_error(described_class) do |error|
          expect(error.status).to eq(status)
          expect(error.url).to eq(url)
          expect(error.message).to eq("HTTP #{status} for https://example.com/missing")
        end
      end
    end

    it 'returns nil for non-deterministic statuses', :aggregate_failures do
      [200, 301, 403, 429, 500, 503].each do |status|
        expect(described_class.check!(response_with.call(status))).to be_nil
      end
    end
  end

  describe '#initialize' do
    it 'keeps the message and defaults status and url to nil', :aggregate_failures do
      error = described_class.new('x')

      expect(error.message).to eq('x')
      expect(error.status).to be_nil
      expect(error.url).to be_nil
    end

    it 'stores the given status and url', :aggregate_failures do
      error = described_class.new('x', status: 410, url:)

      expect(error.status).to eq(410)
      expect(error.url).to eq(url)
    end
  end

  describe '#diagnostics' do
    it 'includes the status' do
      expect(described_class.new('x', status: 404).diagnostics).to eq(status: 404)
    end

    it 'stays sparse without a status' do
      expect(described_class.new('x').diagnostics).to eq({})
    end

    it 'merges the status into the attempt diagnostics' do
      error = described_class.new('x', status: 404)
      error.attempts = [{ strategy: :default }]

      expect(error.diagnostics).to eq(strategy_attempts: [{ strategy: :default }], status: 404)
    end
  end
end
