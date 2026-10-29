# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Budget do
  describe '.new' do
    it 'rejects non-positive request slot limits' do
      expect { described_class.new(max_requests: 0) }
        .to raise_error(ArgumentError, 'max_requests must be positive')
    end

    it 'rejects non-integer request slot limits' do
      expect { described_class.new(max_requests: 1.5) }
        .to raise_error(ArgumentError, 'max_requests must be positive')
    end
  end

  describe '#consume!' do
    let(:budget) { described_class.new(max_requests: 2) }
    let(:mutex) { instance_double(Mutex) }

    before do
      allow(Mutex).to receive(:new).and_return(mutex)
      allow(mutex).to receive(:synchronize).and_yield
    end

    it 'decrements the remaining request budget', :aggregate_failures do
      expect { budget.consume! }.to change(budget, :remaining).from(2).to(1)
      expect { budget.consume! }.to change(budget, :remaining).from(1).to(0)
    end

    it 'synchronizes consumption with the mutex' do
      budget.consume!
      expect(mutex).to have_received(:synchronize)
    end

    it 'raises once no request slots remain' do
      2.times { budget.consume! }

      expect do
        budget.consume!
      end.to raise_error(Html2rss::RequestService::RequestBudgetExceeded, 'Request budget exhausted')
    end
  end

  describe '#remaining_requests' do
    let(:mutex) { instance_double(Mutex) }

    before do
      allow(Mutex).to receive(:new).and_return(mutex)
      allow(mutex).to receive(:synchronize).and_yield
    end

    it 'synchronizes reading remaining requests with the mutex', :aggregate_failures do
      expect(described_class.new(max_requests: 2).remaining_requests).to eq(2)
      expect(mutex).to have_received(:synchronize)
    end
  end

  describe '#elapsed_seconds' do
    it 'reports wall-clock time since budget creation' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 105.0)

      budget = described_class.new(max_requests: 2)
      expect(budget.elapsed_seconds).to eq(5.0)
    end
  end

  describe '#remaining_timeout_seconds' do
    it 'returns nil when total_timeout_seconds is not provided' do
      budget = described_class.new(max_requests: 2)
      expect(budget.remaining_timeout_seconds).to be_nil
    end

    it 'returns the remaining time' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 103.0)

      budget = described_class.new(max_requests: 2, total_timeout_seconds: 10)
      expect(budget.remaining_timeout_seconds).to eq(7.0)
    end

    it 'clamps to zero when time has expired' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 115.0)

      budget = described_class.new(max_requests: 2, total_timeout_seconds: 10)
      expect(budget.remaining_timeout_seconds).to eq(0.0)
    end
  end

  describe '#effective_timeout_seconds' do
    it 'owns remaining-or-fallback resolution as float so adapters do not reimplement it', :aggregate_failures do
      budget = described_class.new(max_requests: 2)

      expect(budget.effective_timeout_seconds(fallback: 30)).to be_a(Float)
      expect(budget.effective_timeout_seconds(fallback: 30.5)).to eq(30.5)
    end

    it 'raises when the tracked deadline is exhausted' do
      budget = described_class.new(max_requests: 2, total_timeout_seconds: 0)

      expect { budget.effective_timeout_seconds(fallback: 30) }
        .to raise_error(Html2rss::RequestService::RequestTimedOut, 'Request timed out')
    end

    it 'raises when fallback is non-positive' do
      budget = described_class.new(max_requests: 2)

      expect { budget.effective_timeout_seconds(fallback: -1) }
        .to raise_error(Html2rss::RequestService::RequestTimedOut, 'Request timed out')
    end

    it 'permits sub-second timeouts above zero' do
      budget = described_class.new(max_requests: 2)

      expect(budget.effective_timeout_seconds(fallback: 0.5)).to eq(0.5)
    end
  end

  describe '#effective_timeout_ms' do
    it 'converts the effective timeout to integer milliseconds for browser protocol APIs' do
      budget = described_class.new(max_requests: 2)

      expect(budget.effective_timeout_ms(fallback: 12.5)).to be(12_500)
    end
  end
end
