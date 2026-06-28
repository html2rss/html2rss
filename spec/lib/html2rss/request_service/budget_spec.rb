# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Budget do
  describe '#consume!' do
    let(:budget) { described_class.new(max_requests: 2) }

    it 'decrements the remaining budget', :aggregate_failures do
      expect { budget.consume! }.to change(budget, :remaining).from(2).to(1)
      expect { budget.consume! }.to change(budget, :remaining).from(1).to(0)
    end

    it 'raises once no requests remain' do
      2.times { budget.consume! }

      expect do
        budget.consume!
      end.to raise_error(Html2rss::RequestService::RequestBudgetExceeded, 'Request budget exhausted')
    end
  end

  describe '#remaining_timeout_seconds' do
    it 'returns nil when total_timeout_seconds is not provided' do
      budget = described_class.new(max_requests: 2)
      expect(budget.remaining_timeout_seconds).to be_nil
    end

    it 'returns the remaining time' do
      budget = described_class.new(max_requests: 2, total_timeout_seconds: 10)
      expect(budget.remaining_timeout_seconds).to be_within(0.5).of(10)
    end
  end
end
