# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Budget do
  describe '.new' do
    it 'rejects non-positive request slot limits' do
      expect { described_class.new(max_requests: 0, total_timeout_seconds: 60) }
        .to raise_error(Html2rss::InvalidOption, /max_requests must be an Integer in 1\.\./)
    end

    it 'rejects non-integer request slot limits' do
      expect { described_class.new(max_requests: 1.5, total_timeout_seconds: 60) }
        .to raise_error(Html2rss::InvalidOption, /max_requests must be an Integer in 1\.\./)
    end
  end

  describe '#consume!' do
    let(:budget) { described_class.new(max_requests: 2, total_timeout_seconds: 60) }
    let(:mutex) { instance_double(Mutex) }

    before do
      allow(Mutex).to receive(:new).and_return(mutex)
      allow(mutex).to receive(:synchronize).and_yield
    end

    it 'decrements the remaining request budget', :aggregate_failures do
      expect { budget.consume! }.to change(budget, :remaining_requests).from(2).to(1)
      expect { budget.consume! }.to change(budget, :remaining_requests).from(1).to(0)
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
      expect(described_class.new(max_requests: 2, total_timeout_seconds: 60).remaining_requests).to eq(2)
      expect(mutex).to have_received(:synchronize)
    end
  end

  describe '#elapsed_seconds' do
    it 'reports wall-clock time since budget creation' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 105.0)

      budget = described_class.new(max_requests: 2, total_timeout_seconds: 60)
      expect(budget.elapsed_seconds).to eq(5.0)
    end
  end

  describe '#remaining_timeout_seconds' do
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
    it 'returns the remaining time as a float so adapters do not reimplement it' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 103.5)

      budget = described_class.new(max_requests: 2, total_timeout_seconds: 10)
      expect(budget.effective_timeout_seconds).to eq(6.5)
    end

    it 'raises when the deadline is exhausted' do
      budget = described_class.new(max_requests: 2, total_timeout_seconds: 0)

      expect { budget.effective_timeout_seconds }
        .to raise_error(Html2rss::RequestService::RequestTimedOut, 'Request timed out')
    end

    it 'permits sub-second timeouts above zero' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0, 109.5)

      budget = described_class.new(max_requests: 2, total_timeout_seconds: 10)
      expect(budget.effective_timeout_seconds).to eq(0.5)
    end
  end
end
