# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ReplayBreaker do
  subject(:breaker) { described_class.new }

  let(:max) { described_class::MAX_BLOCKS }
  let(:clock) { { now: 100.0 } }
  let(:state) { breaker.instance_variable_get(:@state) }

  before do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock[:now] }
  end

  describe '#open?' do
    it 'is closed for unknown keys' do
      expect(breaker.open?('k')).to be false
    end

    it 'stays closed below the block threshold' do
      (max - 1).times { breaker.record_block('k', ttl: 60) }

      expect(breaker.open?('k')).to be false
    end

    it 'closes again once the ttl elapsed' do
      max.times { breaker.record_block('k', ttl: 0) }

      expect(breaker.open?('k')).to be false
    end

    it 'stays open until the ttl elapses and closes at the exact expiry instant', :aggregate_failures do
      max.times { breaker.record_block('k', ttl: 60) }

      clock[:now] = 159.999
      expect(breaker.open?('k')).to be true

      clock[:now] = 160.0
      expect(breaker.open?('k')).to be false
    end

    it 'reads state through its mutex' do
      mutex = breaker.instance_variable_get(:@mutex)
      allow(mutex).to receive(:synchronize).and_call_original

      breaker.open?('k')

      expect(mutex).to have_received(:synchronize)
    end

    it 'keeps a live key in state on read' do
      max.times { breaker.record_block('k', ttl: 60) }

      clock[:now] = 159.999
      breaker.open?('k')

      expect(state.keys).to eq(['k'])
    end

    it 'drops the expired key from state on read' do
      max.times { breaker.record_block('k', ttl: 60) }

      clock[:now] = 160.0
      breaker.open?('k')

      expect(state).to be_empty
    end
  end

  describe '#record_block' do
    it 'reports whether the block tripped the breaker', :aggregate_failures do
      results = Array.new(max) { breaker.record_block('k', ttl: 60) }

      expect(results.first(max - 1)).to all(be(false))
      expect(results.last).to be true
      expect(breaker.open?('k')).to be true
    end

    it 'tracks keys independently', :aggregate_failures do
      max.times { breaker.record_block('a', ttl: 60) }

      expect(breaker.open?('a')).to be true
      expect(breaker.open?('b')).to be false
    end

    it 'stores the block count without an expiry below the threshold' do
      (max - 1).times { breaker.record_block('k', ttl: 60) }

      expect(state['k']).to eq([max - 1, nil])
    end

    it 'stores the count with an expiry at now plus ttl once tripped' do
      max.times { breaker.record_block('k', ttl: 60) }

      expect(state['k']).to eq([max, 160.0])
    end

    it 'writes state through its mutex' do
      mutex = breaker.instance_variable_get(:@mutex)
      allow(mutex).to receive(:synchronize).and_call_original

      breaker.record_block('k', ttl: 60)

      expect(mutex).to have_received(:synchronize)
    end

    it 'keeps reporting a trip for blocks past the threshold' do
      max.times { breaker.record_block('k', ttl: 60) }

      expect(breaker.record_block('k', ttl: 60)).to be true
    end
  end

  describe '#record_pass' do
    it 'resets the consecutive block count', :aggregate_failures do
      (max - 1).times { breaker.record_block('k', ttl: 60) }
      breaker.record_pass('k')

      expect(breaker.record_block('k', ttl: 60)).to be false
      expect(breaker.open?('k')).to be false
    end

    it 'clears only the given key and keeps the others counting', :aggregate_failures do
      max.times { breaker.record_block('a', ttl: 60) }
      (max - 1).times { breaker.record_block('b', ttl: 60) }
      breaker.record_pass('a')

      expect(breaker.open?('a')).to be false
      expect(breaker.record_block('b', ttl: 60)).to be true
    end

    it 'serializes state changes through its mutex' do
      mutex = breaker.instance_variable_get(:@mutex)
      allow(mutex).to receive(:synchronize).and_call_original

      breaker.record_pass('k')

      expect(mutex).to have_received(:synchronize)
    end
  end
end
