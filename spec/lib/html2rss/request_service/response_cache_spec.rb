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
    it 'reuses a fresh entry', :aggregate_failures do
      first = fetcher.call(:a)

      expect(fetcher.call(:a)).to be(first)
      expect(calls).to eq([:a])
    end

    it 'refetches once the ttl has elapsed' do
      fetcher.call(:a)
      clock_time[0] = 110
      fetcher.call(:a)

      expect(calls).to eq(%i[a a])
    end

    it 'stores exactly the 2xx statuses', :aggregate_failures do
      statuses = [199, 200, 299, 300, nil].to_h do |status|
        response = Html2rss::RequestService::Response.new(body: 'x', url: 'https://example.com/', status:)
        [status, 2.times.count { cache.fetch(status) { response.tap { calls << status } } } && calls.count(status) == 1]
      end

      expect(statuses).to eq(199 => false, 200 => true, 299 => true, 300 => false, nil => false)
    end

    it 'does not store non-2xx responses' do
      2.times { fetcher.call(:a, blocked) }

      expect(calls).to eq(%i[a a])
    end

    it 'treats an entry as fresh strictly before its expiry' do
      fetcher.call(:a)
      clock_time[0] = 109
      fetcher.call(:a)

      expect(calls).to eq([:a])
    end

    it 'moves a refetched entry to the newest position' do
      [[100, :a], [105, :b], [111, :a], [111, :c], [111, :a]].each do |at, key|
        clock_time[0] = at
        fetcher.call(key)
      end

      expect(calls).to eq(%i[a b a c])
    end
  end

  describe '#initialize' do
    it 'defaults to a real clock and a 64 entry bound', :aggregate_failures do
      real = described_class.new(ttl: 60)
      (0..64).each { |key| real.fetch(key) { ok } }

      expect(real.fetch(64) { raise 'refetched' }).to be(ok)
      expect { real.fetch(0) { raise 'refetched' } }.to raise_error('refetched')
    end

    it 'accepts a single entry' do
      single = described_class.new(ttl: 1, max_entries: 1)
      single.fetch(:a) { ok }

      expect(single.fetch(:a) { raise 'refetched' }).to be(ok)
    end

    it 'rejects a non-positive max_entries' do
      expect { described_class.new(ttl: 1, max_entries: 0) }.to raise_error(Html2rss::InvalidOption, /max_entries must/)
    end

    it 'rejects a non-integer ttl' do
      expect { described_class.new(ttl: nil) }.to raise_error(Html2rss::InvalidOption, /ttl must be/)
    end

    it 'rejects a non-positive ttl' do
      expect { described_class.new(ttl: 0) }.to raise_error(Html2rss::InvalidOption, /ttl must be/)
    end
  end
end
