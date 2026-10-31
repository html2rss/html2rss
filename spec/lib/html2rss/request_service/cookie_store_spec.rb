# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::CookieStore do
  subject(:store) { described_class.new }

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
  end

  describe '#evict' do
    it 'removes the entry' do
      store.write('k', { 'a' => '1' }, ttl: 60)
      store.evict('k')

      expect(store.fetch('k')).to eq({})
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
  end
end
