# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Budget do
  describe '.new' do
    it 'rejects non-positive request slot limits' do
      expect { described_class.new(max_requests: 0) }
        .to raise_error(ArgumentError, 'max_requests must be positive')
    end

    it 'rejects negative interaction slot limits' do
      expect { described_class.new(max_requests: 1, max_interactions: -1) }
        .to raise_error(ArgumentError, 'max_interactions must be a non-negative integer')
    end
  end

  describe '#consume!' do
    let(:budget) { described_class.new(max_requests: 2) }

    it 'decrements the remaining request budget', :aggregate_failures do
      expect { budget.consume! }.to change(budget, :remaining).from(2).to(1)
      expect { budget.consume! }.to change(budget, :remaining).from(1).to(0)
    end

    it 'raises once no request slots remain' do
      2.times { budget.consume! }

      expect do
        budget.consume!
      end.to raise_error(Html2rss::RequestService::RequestBudgetExceeded, 'Request budget exhausted')
    end
  end

  describe '#consume_interaction!' do
    let(:budget) { described_class.new(max_requests: 2, max_interactions: 2) }

    it 'decrements interaction budget without stealing request slots', :aggregate_failures do
      expect { budget.consume_interaction! }.to change(budget, :remaining_interactions).from(2).to(1)
      expect(budget.remaining_requests).to eq(2)
    end

    it 'raises once no interaction slots remain' do
      2.times { budget.consume_interaction! }

      expect do
        budget.consume_interaction!
      end.to raise_error(Html2rss::RequestService::InteractionBudgetExceeded, 'Interaction budget exhausted')
    end
  end

  describe '#elapsed_seconds' do
    it 'reports wall-clock time since budget creation' do
      budget = described_class.new(max_requests: 2)
      expect(budget.elapsed_seconds).to be >= 0.0
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

  describe '#effective_timeout_seconds' do
    it 'owns remaining-or-fallback resolution so adapters do not reimplement it' do
      budget = described_class.new(max_requests: 2)

      expect(budget.effective_timeout_seconds(fallback: 30)).to eq(30.0)
    end

    it 'raises when the tracked deadline is exhausted' do
      budget = described_class.new(max_requests: 2, total_timeout_seconds: 0)

      expect { budget.effective_timeout_seconds(fallback: 30) }
        .to raise_error(Html2rss::RequestService::RequestTimedOut, 'Request timed out')
    end
  end

  describe '#effective_timeout_ms' do
    it 'converts the effective timeout for browser protocol APIs' do
      budget = described_class.new(max_requests: 2)

      expect(budget.effective_timeout_ms(fallback: 12)).to eq(12_000)
    end
  end
end
