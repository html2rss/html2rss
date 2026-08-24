# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline::RuntimePolicy do
  subject(:runtime_policy) { described_class.from_config(config) }

  let(:raw_config) do
    {
      strategy: :botasaurus,
      request: { max_redirects: 8 },
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

  # Default auto_source reserves NativeFeed + entry_resolution probes on top of
  # wordpress_api/sitemap/pagination; that baseline exceeds Policy::MAX_REQUESTS_CEILING.
  let(:request_ceiling) { Html2rss::RequestService::Policy::MAX_REQUESTS_CEILING }

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

      it 'sizes HTTP request slots up to the policy ceiling', :aggregate_failures do
        expect(runtime_policy.max_requests).to eq(request_ceiling)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end

    context 'when strategy is auto and max_requests is omitted' do
      let(:config) { Html2rss::Config.from_hash(raw_config.merge(strategy: :auto)) }

      it 'includes auto fallback retry slots but still clamps to the policy ceiling', :aggregate_failures do
        baseline = described_class.send(:baseline_request_budget_for, config)
        expected_retry_budget = Html2rss::FeedPipeline::AutoFallback::CHAIN.size - 1

        expect(baseline).to be >= (1 + expected_retry_budget)
        expect(runtime_policy.max_requests).to eq(request_ceiling)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end

    context 'when strategy is non-auto and max_requests is omitted' do
      let(:config) { Html2rss::Config.from_hash(raw_config.merge(strategy: :faraday)) }

      it 'keeps non-auto baselines under the same policy ceiling' do
        expect(runtime_policy.max_requests).to eq(request_ceiling)
      end
    end

    context 'when pagination strategy omits max_pages' do
      let(:config) do
        Html2rss::Config.from_hash(
          raw_config.merge(
            strategy: :faraday,
            selectors: raw_config[:selectors].merge(
              items: { selector: 'article', pagination: { strategy: 'url_template' } }
            )
          )
        )
      end

      it 'reserves request budget using default max_pages of 5 (clamped to ceiling)' do
        # 1 initial + (5-1) pagination + scrapers + entry_resolution → ceiling
        expect(runtime_policy.max_requests).to eq(request_ceiling)
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

    context 'when total_timeout_seconds is configured' do
      let(:config) { Html2rss::Config.from_hash(raw_config.merge(request: raw_config[:request].merge(total_timeout_seconds: 42))) }

      it 'passes the timeout to the policy' do
        expect(runtime_policy.total_timeout_seconds).to eq(42)
      end
    end
  end

  describe '.budget_for' do
    let(:config) { Html2rss::Config.from_hash(raw_config) }

    it 'builds a Budget with request pools', :aggregate_failures do
      budget = described_class.budget_for(config)

      expect(budget.remaining_requests).to eq(request_ceiling)
    end
  end
end
