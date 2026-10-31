# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ReplayBreaker do
  subject(:breaker) { described_class.new }

  let(:max) { described_class::MAX_BLOCKS }

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
  end

  describe '#record_pass' do
    it 'resets the consecutive block count', :aggregate_failures do
      (max - 1).times { breaker.record_block('k', ttl: 60) }
      breaker.record_pass('k')

      expect(breaker.record_block('k', ttl: 60)).to be false
      expect(breaker.open?('k')).to be false
    end
  end
end
