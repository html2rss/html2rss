# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession::RuntimePolicy do
  subject(:runtime_policy) { described_class.from_config(config) }

  let(:raw_config) do
    {
      strategy: :browserless,
      request: { max_redirects: 8, browserless: { preload: { wait_after_ms: 500 } } },
      channel: { url: 'https://example.com/blog' },
      selectors: {
        items: { selector: 'article', pagination: { max_pages: 3 } },
        title: { selector: 'h2' }
      },
      auto_source: Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG.fetch(:scraper).merge(
          wordpress_api: { enabled: true }
        )
      )
    }
  end

  describe '.from_config' do
    context 'when max_requests is explicitly configured' do
      let(:config) { Html2rss::Config.from_hash(raw_config.merge(request: raw_config[:request].merge(max_requests: 1))) }

      it 'preserves the explicit request ceiling', :aggregate_failures do
        expect(runtime_policy.max_requests).to eq(1)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end

    context 'when max_requests is omitted' do
      let(:config) { Html2rss::Config.from_hash(raw_config) }

      it 'adds predictable follow-up budget to the runtime policy', :aggregate_failures do
        expect(runtime_policy.max_requests).to eq(6)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end

    context 'when strategy is auto and max_requests is omitted' do
      let(:config) { Html2rss::Config.from_hash(raw_config.merge(strategy: :auto)) }

      it 'adds auto fallback retry budget to the runtime policy', :aggregate_failures do
        expected_retry_budget = Html2rss::RequestService::AutoStrategy::CHAIN.size - 1

        expect(runtime_policy.max_requests).to eq(6 + expected_retry_budget)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end

    context 'when strategy is non-auto and max_requests is omitted' do
      let(:config) { Html2rss::Config.from_hash(raw_config.merge(strategy: :faraday)) }

      it 'keeps baseline budget unchanged for non-auto strategies' do
        expect(runtime_policy.max_requests).to eq(6)
      end
    end

    context 'when strategy is auto and max_requests is explicitly configured' do
      let(:config) do
        Html2rss::Config.from_hash(
          raw_config.merge(strategy: :auto, request: raw_config[:request].merge(max_requests: 2))
        )
      end

      it 'preserves the explicit request ceiling' do
        expect(runtime_policy.max_requests).to eq(2)
      end
    end

    context 'when browserless preload is omitted' do
      let(:config) do
        Html2rss::Config.from_hash(
          raw_config.merge(request: { max_redirects: 8 })
        )
      end

      it 'does not reserve preload budget', :aggregate_failures do
        expect(runtime_policy.max_requests).to eq(4)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end

    context 'when preload only clicks without waits' do
      let(:config) do
        Html2rss::Config.from_hash(
          raw_config.merge(
            request: {
              max_redirects: 8,
              browserless: { preload: { click_selectors: [{ selector: '.load-more', max_clicks: 2 }] } }
            }
          )
        )
      end

      it 'counts click actions without extra wait budget' do
        expect(runtime_policy.max_requests).to eq(6)
      end
    end

    context 'when preload only scrolls without waits' do
      let(:config) do
        Html2rss::Config.from_hash(
          raw_config.merge(
            request: {
              max_redirects: 8,
              browserless: { preload: { scroll_down: { iterations: 3 } } }
            }
          )
        )
      end

      it 'counts scroll actions without extra wait budget' do
        expect(runtime_policy.max_requests).to eq(7)
      end
    end
  end
end
