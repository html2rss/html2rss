# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ResponseCache do
  subject(:cache) { described_class.new(ttl: 10) }

  let(:build) do
    ->(status = 200) { Html2rss::RequestService::Response.new(body: 'ok', url: 'https://example.com/', status:) }
  end
  let(:gate) { Queue.new }
  let(:fetches) { Queue.new }
  let(:slow_fetch) do
    lambda do |response = build.call|
      fetches << true
      gate.pop
      response || raise('boom')
    end
  end

  describe '#fetch' do
    it 'fetches once for N concurrent misses, each caller getting its own replica' do
      results = release_and_settle(gate, spawn_threads(3) { cache.fetch(:a) { slow_fetch.call } })

      expect([fetches.size, results.map(&:body).uniq, results.map(&:object_id).uniq.size]).to eq([1, ['ok'], 3])
    end

    it 'does not cache a failed fetch and releases waiters', :aggregate_failures do
      leader = spawn_threads(1) { cache.fetch(:a) { slow_fetch.call(nil) } }
      wait_until_parked(leader)
      waiters = spawn_threads(3) { cache.fetch(:a, &slow_fetch) }
      results = release_and_settle(gate, leader + waiters)

      expect([results.first.class, results.drop(1).map(&:body), fetches.size]).to eq([RuntimeError, %w[ok ok ok], 2])
    end

    it 'lets waiters fetch for themselves when the response is uncacheable', :aggregate_failures do
      results = release_and_settle(gate, spawn_threads(3) { cache.fetch(:a) { slow_fetch.call(build.call(403)) } })

      expect(results.map(&:status)).to eq([403, 403, 403])
      expect(fetches.size).to eq(3)
    end

    it 'does not block different keys on each other' do
      leader = spawn_threads(1) { cache.fetch(:a, &slow_fetch) }
      wait_until_parked(leader)

      expect(cache.fetch(:b) { build.call }.body).to eq('ok')
      release_and_settle(gate, leader)
    end
  end
end
