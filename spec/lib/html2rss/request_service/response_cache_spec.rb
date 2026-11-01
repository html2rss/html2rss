# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ResponseCache do
  subject(:cache) { described_class.new(ttl: 10, max_entries: 2, clock: -> { clock_time.first }) }

  let(:clock_time) { [100] }
  let(:ok) { Html2rss::RequestService::Response.new(body: 'ok', url: 'https://example.com/', status: 200) }
  let(:blocked) { Html2rss::RequestService::Response.new(body: 'no', url: 'https://example.com/', status: 403) }
  let(:calls) { [] }
  let(:fetcher) { ->(key, response = ok) { cache.fetch(key) { response.tap { calls << key } } } }

  describe '#fetch' do
    it 'serves a fresh entry as an aged replica', :aggregate_failures do
      fetcher.call(:a)
      clock_time[0] = 104.9
      hit = fetcher.call(:a)

      expect(calls).to eq([:a])
      expect([hit.body, hit.cache_age, hit.equal?(ok)]).to eq(['ok', 4, false])
    end

    it 'returns the live response, untagged, on a miss' do
      expect(fetcher.call(:a).cache_age).to be_nil
    end

    it 'refetches once the ttl has elapsed' do
      fetcher.call(:a)
      clock_time[0] = 110
      fetcher.call(:a)

      expect(calls).to eq(%i[a a])
    end

    it 'treats an entry as fresh strictly before its expiry' do
      fetcher.call(:a)
      clock_time[0] = 109
      fetcher.call(:a)

      expect(calls).to eq([:a])
    end

    { 199 => false, 200 => true, 299 => true, 300 => false, nil => false }.each do |status, stored|
      it "#{stored ? 'stores' : 'skips'} status #{status.inspect}" do
        response = Html2rss::RequestService::Response.new(body: 'x', url: 'https://example.com/', status:)
        2.times { fetcher.call(:a, response) }

        expect(calls.size).to eq(stored ? 1 : 2)
      end
    end

    it 'does not store when the block raises', :aggregate_failures do
      expect { cache.fetch(:a) { raise 'boom' } }.to raise_error('boom')
      fetcher.call(:a)

      expect(calls).to eq([:a])
    end

    it 'evicts the oldest entry beyond max_entries' do
      %i[a b c a].each { |key| fetcher.call(key) }

      expect(calls).to eq(%i[a b c a])
    end

    it 'moves a refetched entry to the newest position' do
      [[100, :a], [105, :b], [111, :a], [111, :c], [111, :a]].each do |at, key|
        clock_time[0] = at
        fetcher.call(key)
      end

      expect(calls).to eq(%i[a b a c])
    end
  end

  describe 'byte budget' do
    subject(:cache) { described_class.new(ttl: 10, max_bytes: 10, clock: -> { clock_time.first }) }

    let(:fetcher) do
      lambda do |key, size|
        response = Html2rss::RequestService::Response.new(body: 'x' * size, url: 'https://example.com/', status: 200)
        cache.fetch(key) { response.tap { calls << key } }
      end
    end

    it 'evicts oldest entries until the summed bodies fit', :aggregate_failures do
      %i[a b c b c a].each { |key| fetcher.call(key, 4) }

      expect(calls).to eq(%i[a b c a])
    end

    it 'keeps the budget exact when a key is replaced' do
      fetcher.call(:a, 6)
      clock_time[0] = 110
      2.times { fetcher.call(:a, 6) }

      expect(calls).to eq(%i[a a])
    end

    it 'stores a body that exactly fills the budget' do
      2.times { fetcher.call(:a, 10) }

      expect(calls).to eq([:a])
    end

    it 'never stores a body larger than the budget, nor evicts others for it', :aggregate_failures do
      [[:a, 4], [:big, 11], [:big, 11], [:a, 4]].each { |key, size| fetcher.call(key, size) }

      expect(calls).to eq(%i[a big big])
    end
  end

  describe '#initialize' do
    it 'exposes the ttl' do
      expect(described_class.new(ttl: 7).ttl).to eq(7)
    end

    it 'defaults to a real clock, 32 entries and 32 MiB', :aggregate_failures do
      real = described_class.new(ttl: 60)
      (0..32).each { |key| real.fetch(key) { ok } }

      expect(real.fetch(32) { raise 'refetched' }.body).to eq('ok')
      expect { real.fetch(0) { raise 'refetched' } }.to raise_error('refetched')
      expect(described_class::DEFAULT_MAX_BYTES).to eq(33_554_432)
    end

    it 'starts with an empty byte count' do
      exact = described_class.new(ttl: 10, max_bytes: 4)
      body = Html2rss::RequestService::Response.new(body: 'xxxx', url: 'https://example.com/', status: 200)
      exact.fetch(:a) { body }

      expect(exact.fetch(:a) { raise 'refetched' }.body).to eq('xxxx')
    end

    it 'counts bytes exactly across entries' do
      exact = described_class.new(ttl: 10, max_bytes: 4)
      [[:a, 'xx'], [:b, 'xxx']].each do |key, body|
        exact.fetch(key) { Html2rss::RequestService::Response.new(body:, url: 'https://example.com/', status: 200) }
      end

      expect { exact.fetch(:a) { raise 'refetched' } }.to raise_error('refetched')
    end

    it 'accepts a one byte budget' do
      expect { described_class.new(ttl: 1, max_bytes: 1) }.not_to raise_error
    end

    it 'accepts a single entry' do
      single = described_class.new(ttl: 1, max_entries: 1)
      single.fetch(:a) { ok }

      expect(single.fetch(:a) { raise 'refetched' }.body).to eq('ok')
    end

    it 'rejects out-of-range options', :aggregate_failures do
      expect { described_class.new(ttl: 0) }.to raise_error(Html2rss::InvalidOption, /ttl must/)
      expect { described_class.new(ttl: nil) }.to raise_error(Html2rss::InvalidOption, /ttl must/)
      expect { described_class.new(ttl: 1, max_entries: 0) }.to raise_error(Html2rss::InvalidOption, /max_entries must/)
      expect { described_class.new(ttl: 1, max_bytes: 0) }.to raise_error(Html2rss::InvalidOption, /max_bytes must/)
    end
  end
end
