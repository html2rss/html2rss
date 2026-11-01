# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ResponseCaching do
  let(:service) { Html2rss::RequestService }
  let(:global) { Html2rss::RequestService::ResponseCache.new(ttl: 60) }
  let(:scoped) { Html2rss::RequestService::ResponseCache.new(ttl: 60) }

  after { service.response_cache = nil }

  describe '#with_response_cache' do
    it 'takes precedence over the global cache and returns the block result', :aggregate_failures do
      service.response_cache = global

      expect(service.with_response_cache(scoped) { [service.response_cache, :done] }).to eq([scoped, :done])
      expect(service.response_cache).to be(global)
    end

    it 'restores the previous scope when the block raises', :aggregate_failures do
      service.response_cache = global

      expect { service.with_response_cache(scoped) { raise 'boom' } }.to raise_error('boom')
      expect(service.response_cache).to be(global)
    end

    it 'restores the unscoped state after a raise with no global cache', :aggregate_failures do
      expect { service.with_response_cache(scoped) { raise 'boom' } }.to raise_error('boom')
      expect(service.response_cache).to be_nil
    end

    it 'nests and restores the outer scope', :aggregate_failures do
      seen = service.with_response_cache(scoped) do
        [service.with_response_cache(:inner) { service.response_cache }, service.response_cache]
      end

      expect(seen).to eq([:inner, scoped])
      expect(service.response_cache).to be_nil
    end

    it 'disables caching inside the block when given nil', :aggregate_failures do
      service.response_cache = global

      expect(service.with_response_cache(nil) { service.response_cache }).to be_nil
      expect(service.response_cache).to be(global)
    end

    it 'is inherited by threads spawned inside the block', :aggregate_failures do
      spawned = service.with_response_cache(scoped) { spawn_threads(1) { service.response_cache } }

      expect(settle(spawned)).to eq([scoped])
      expect(settle(spawn_threads(1) { service.response_cache })).to eq([nil])
    end
  end

  describe 'initial fetches inside a scope' do
    let(:strategy_instance) { instance_double(Html2rss::RequestService::HttpxStrategy) }
    let(:context) do
      instance_double(
        Html2rss::RequestService::Context,
        relation: :initial, headers: {}, request: {}, policy: Html2rss::RequestService::Policy.default,
        url: instance_double(Html2rss::Url, host: 'example.com', to_s: 'https://example.com/')
      )
    end

    before do
      allow(Html2rss::RequestService::HttpxStrategy).to receive(:new).and_return(strategy_instance)
      allow(strategy_instance).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(body: '<html></html>', url: 'https://example.com/', status: 200)
      )
    end

    it 'cache through the scoped cache only', :aggregate_failures do
      service.with_response_cache(scoped) { 2.times { service.execute(context, strategy: :default) } }
      service.execute(context, strategy: :default)

      expect(strategy_instance).to have_received(:execute).twice
    end
  end
end
