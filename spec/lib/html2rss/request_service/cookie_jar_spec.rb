# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::CookieJar do
  subject(:jar) do
    described_class.new(host: 'a.test', scraper_base_url: 'http://s', proxy: nil, user_agent: 'UA', store:)
  end

  let(:store) { instance_double(Html2rss::RequestService::CookieStore, fetch: {}, write: nil, evict: nil) }
  let(:key) do
    Html2rss::RequestService::CookieStore.key(
      host: 'a.test', scraper_base_url: 'http://s', proxy: nil, user_agent: 'UA'
    )
  end
  let(:proxied_key) do
    Html2rss::RequestService::CookieStore.key(
      host: 'a.test', scraper_base_url: 'http://s', proxy: 'http://p:1', user_agent: 'UA'
    )
  end
  let(:logs) { [] }

  before do
    allow(Html2rss::Log).to receive(:info) { |line| logs << JSON.parse(line) }
  end

  after { Html2rss::RequestService.cookie_store = nil }

  describe '#initialize' do
    it 'uses the configured RequestService store by default', :aggregate_failures do
      Html2rss::RequestService.cookie_store = store
      described_class.new(host: 'a.test', scraper_base_url: 'http://s', proxy: nil, user_agent: 'UA').stored

      expect(store).to have_received(:fetch).with(key)
    end

    it 'scopes the jar key by proxy' do
      described_class.new(host: 'a.test', scraper_base_url: 'http://s', proxy: 'http://p:1', user_agent: 'UA', store:)
                     .stored

      expect(store).to have_received(:fetch).with(proxied_key)
    end

    it 'keeps the host it was built for in its telemetry' do
      allow(store).to receive(:fetch).with(key).and_return('a' => '1')
      jar.stored

      expect(logs.first).to include('host' => 'a.test')
    end
  end

  describe '#stored' do
    it 'returns the live cookies held under the jar key', :aggregate_failures do
      allow(store).to receive(:fetch).with(key).and_return('a' => '1')

      expect(jar.stored).to eq('a' => '1')
      expect(store).to have_received(:fetch).with(key)
    end

    it 'returns {} and logs nothing when the store has no cookies', :aggregate_failures do
      expect(jar.stored).to eq({})
      expect(logs).to be_empty
    end

    it 'logs a replay event with the count and no cookie values' do
      allow(store).to receive(:fetch).with(key).and_return('a' => 'secret-1', 'b' => 'secret-2')
      jar.stored

      expect(logs).to eq(
        [{ 'event_name' => 'botasaurus.cookie_jar', 'action' => 'replay', 'host' => 'a.test', 'cookie_count' => 2 }]
      )
    end
  end

  describe '#refresh' do
    it 'writes the stored cookies merged with the earned ones under the jar key with the default ttl',
       :aggregate_failures do
      jar.refresh({ 'a' => 'old', 'keep' => 'k' }, { 'a' => 'new', 'b' => '2' })

      expect(store).to have_received(:write).with(
        key, { 'a' => 'new', 'keep' => 'k', 'b' => '2' }, ttl: Html2rss::RequestService::CookieStore::DEFAULT_TTL_SECONDS
      )
    end

    it 'logs a refresh event with the earned count', :aggregate_failures do
      jar.refresh({}, { 'a' => '1', 'b' => '2' })

      expect(logs).to eq(
        [{ 'event_name' => 'botasaurus.cookie_jar', 'action' => 'refresh', 'host' => 'a.test', 'cookie_count' => 2 }]
      )
    end

    it 'does nothing when the scrape earned no cookies', :aggregate_failures do
      jar.refresh({ 'a' => '1' }, {})

      expect(store).not_to have_received(:write)
      expect(logs).to be_empty
    end

    it 'does nothing when reuse is disabled with a zero ttl', :aggregate_failures do
      stub_const('Html2rss::RequestService::CookieStore::DEFAULT_TTL_SECONDS', 0)
      jar.refresh({ 'a' => '1' }, { 'b' => '2' })

      expect(store).not_to have_received(:write)
      expect(logs).to be_empty
    end

    it 'writes when the ttl is exactly one second', :aggregate_failures do
      stub_const('Html2rss::RequestService::CookieStore::DEFAULT_TTL_SECONDS', 1)
      jar.refresh({}, { 'b' => '2' })

      expect(store).to have_received(:write).with(key, { 'b' => '2' }, ttl: 1)
    end

    it 'does nothing when the ttl is negative', :aggregate_failures do
      stub_const('Html2rss::RequestService::CookieStore::DEFAULT_TTL_SECONDS', -1)
      jar.refresh({ 'a' => '1' }, { 'b' => '2' })

      expect(store).not_to have_received(:write)
      expect(logs).to be_empty
    end
  end

  describe '#evict' do
    it 'evicts the jar key from the store', :aggregate_failures do
      jar.evict({ 'a' => '1' })

      expect(store).to have_received(:evict).with(key)
    end

    it 'logs an evict event with the rejected count', :aggregate_failures do
      jar.evict({ 'a' => '1', 'b' => '2', 'c' => '3' })

      expect(logs).to eq(
        [{ 'event_name' => 'botasaurus.cookie_jar', 'action' => 'evict', 'host' => 'a.test', 'cookie_count' => 3 }]
      )
    end
  end
end
