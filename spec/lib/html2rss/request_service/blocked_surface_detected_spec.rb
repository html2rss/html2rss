# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::BlockedSurfaceDetected do
  describe '#initialize' do
    it 'keeps the message and status', :aggregate_failures do
      error = described_class.new('HTTP 403', status: 403)

      expect(error).to have_attributes(message: 'HTTP 403', status: 403)
    end

    it 'defaults to no status', :aggregate_failures do
      error = described_class.new('Blocked surface detected')

      expect(error.message).to eq('Blocked surface detected')
      expect(error.status).to be_nil
    end
  end

  describe '#diagnostics' do
    it 'includes the status when known' do
      expect(described_class.new('HTTP 429', status: 429).diagnostics).to eq(status: 429)
    end

    it 'keeps the attempt diagnostics next to the status', :aggregate_failures do
      error = described_class.new('HTTP 403', status: 403)
      error.attempts = [{ strategy: :default, error_class: described_class.name }]

      expect(error.diagnostics).to include(status: 403, strategy_attempts: error.attempts)
    end

    it 'stays empty without a status' do
      expect(described_class.new('Blocked surface detected').diagnostics).to eq({})
    end
  end

  describe '#kind' do
    it 'is :blocked' do
      expect(described_class.new('x').kind).to be(:blocked)
    end
  end
end
