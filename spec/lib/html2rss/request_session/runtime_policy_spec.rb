# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession::RuntimePolicy do
  subject(:runtime_policy) { described_class.from_config(config) }

  let(:raw_config) do
    {
      strategy: :browserless,
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
        expect(runtime_policy.max_requests).to eq(4)
        expect(runtime_policy.max_redirects).to eq(8)
      end
    end
  end
end
