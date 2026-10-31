# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::CookieStore do
  subject(:store) { described_class.new }

  let(:clock) { { now: 100.0 } }
  let(:entries) { store.instance_variable_get(:@entries) }

  before do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock[:now] }
  end

  describe '#fetch' do
    it 'returns {} for unknown keys' do
      expect(store.fetch('nope')).to eq({})
    end

    it 'returns a copy that cannot mutate the stored jar', :aggregate_failures do
      store.write('k', { 'a' => '1' }, ttl: 60)
      store.fetch('k')['a'] = 'changed'

      expect(store.fetch('k')).to eq('a' => '1')
    end

    it 'drops entries once the ttl elapsed' do
      store.write('k', { 'a' => '1' }, ttl: 0)

      expect(store.fetch('k')).to eq({})
    end

    it 'replays cookies until the ttl elapses and treats the exact expiry instant as expired', :aggregate_failures do
      store.write('k', { 'a' => '1' }, ttl: 60)

      clock[:now] = 159.999
      expect(store.fetch('k')).to eq('a' => '1')

      clock[:now] = 160.0
      expect(store.fetch('k')).to eq({})
    end

    it 'removes the expired entry from memory on fetch', :aggregate_failures do
      store.write('k', { 'a' => '1' }, ttl: 1)
      clock[:now] = 101.0
      store.fetch('k')

      expect(entries).to be_empty
    end
  end

  describe '#write' do
    it 'stores a frozen copy so later changes to the input do not leak into the jar', :aggregate_failures do
      input = { 'a' => '1' }
      store.write('k', input, ttl: 60)
      input['a'] = 'changed'

      expect(store.fetch('k')).to eq('a' => '1')
      expect(entries['k'].first).to be_frozen
    end

    context 'without an explicit ttl' do
      before do
        stub_const('Html2rss::RequestService::CookieStore::DEFAULT_TTL_SECONDS', 60)
        store.write('k', { 'a' => '1' })
      end

      it 'expires after DEFAULT_TTL_SECONDS, exactly at the boundary', :aggregate_failures do
        clock[:now] = 159.999
        expect(store.fetch('k')).to eq('a' => '1')

        clock[:now] = 160.0
        expect(store.fetch('k')).to eq({})
      end
    end

    it 'purges other entries whose expiry has been reached, keeping live ones', :aggregate_failures do
      store.write('expired', { 'a' => '1' }, ttl: 1)
      store.write('live', { 'b' => '2' }, ttl: 60)
      clock[:now] = 101.0
      store.write('fresh', { 'c' => '3' }, ttl: 60)

      expect(entries.keys).to contain_exactly('live', 'fresh')
    end

    it 'purges entries that expired well before the write', :aggregate_failures do
      store.write('stale', { 'a' => '1' }, ttl: 1)
      clock[:now] = 105.0
      store.write('other', { 'b' => '2' }, ttl: 60)

      expect(entries.keys).to eq(['other'])
    end

    it 'purges an entry at the exact instant it expires', :aggregate_failures do
      store.write('boundary', { 'a' => '1' }, ttl: 1)
      clock[:now] = 101.0
      store.write('other', { 'b' => '2' }, ttl: 60)

      expect(entries.keys).to eq(['other'])
    end
  end

  describe '#evict' do
    it 'removes the entry' do
      store.write('k', { 'a' => '1' }, ttl: 60)
      store.evict('k')

      expect(store.fetch('k')).to eq({})
    end

    it 'leaves other keys untouched' do
      store.write('k', { 'a' => '1' }, ttl: 60)
      store.write('other', { 'b' => '2' }, ttl: 60)
      store.evict('k')

      expect(store.fetch('other')).to eq('b' => '2')
    end
  end

  describe '.key' do
    let(:base) { { host: 'a.test', scraper_base_url: 'http://s', proxy: nil, user_agent: 'UA' } }

    it 'differs per host, scraper, proxy and user agent', :aggregate_failures do
      variants = [{}, { host: 'b.test' }, { scraper_base_url: 'http://t' }, { proxy: 'http://u:secret@p:1' },
                  { user_agent: 'Other' }]
      keys = variants.map { |variant| described_class.key(**base, **variant) }

      expect(keys.uniq.size).to eq(5)
      expect(keys.join).not_to include('secret')
    end

    it 'is the SHA256 of the fields in host, scraper, proxy, user agent order joined by NUL', :aggregate_failures do
      key = described_class.key(host: 'a.test', scraper_base_url: 'http://s', proxy: 'http://p:1', user_agent: 'UA')

      expect(key).to eq(Digest::SHA256.hexdigest(['a.test', 'http://s', 'http://p:1', 'UA'].join("\0")))
    end

    it 'keeps field boundaries so shifted values do not collide', :aggregate_failures do
      left = described_class.key(**base, host: 'ab', scraper_base_url: 'c')
      right = described_class.key(**base, host: 'a', scraper_base_url: 'bc')

      expect(left).not_to eq(right)
    end

    it 'changes when host and proxy swap places', :aggregate_failures do
      original = described_class.key(**base, host: 'x.test', proxy: 'http://y:1')
      swapped = described_class.key(**base, host: 'http://y:1', proxy: 'x.test')

      expect(original).not_to eq(swapped)
    end
  end
end
