# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession do
  subject(:session) { described_class.new(context:, strategy:, logger:) }

  let(:strategy) { :faraday }
  let(:logger) { instance_double(Logger, warn: nil, debug: nil) }
  let(:policy) { Html2rss::RequestService::Policy.new(max_requests: 3) }
  let(:budget) { Html2rss::RequestService::Budget.new(max_requests: 3) }
  let(:context) do
    Html2rss::RequestService::Context.new(
      url: 'https://example.com/news',
      headers: { 'User-Agent' => 'RSpec' },
      policy:,
      budget:
    )
  end

  describe '.for_config' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:config) do
      Html2rss::Config.from_hash({
                                   strategy: :browserless,
                                   max_redirects: 8,
                                   max_requests: 1,
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
                                 })
    end

    it 'reserves the baseline request budget while preserving the configured request settings', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      session = described_class.for_config(config, logger:)
      context = session.instance_variable_get(:@context)

      expect(session).to be_a(described_class)
      expect(context.url.to_s).to eq('https://example.com/blog')
      expect(context.headers).to eq(config.headers)
      expect(context.policy.max_redirects).to eq(8)
      expect(context.policy.max_requests).to eq(4)
    end
  end

  describe '#fetch_initial_response' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).with(context, strategy:).and_return(response)
    end

    it 'requests the initial page, tracks its url, and logs the response summary', :aggregate_failures do
      expect(session.fetch_initial_response).to eq(response)
      expect(session.visited?(response.url)).to be(true)
      expect(logger).to have_received(:debug).with(
        %r{Html2rss::RequestSession: relation=initial request_url=https://example\.com/news final_url=https://example\.com/news status=200 content_type="text/html" bytes=13}
      )
    end
  end

  describe '#follow_up' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://redirected.example.com/news?page=2'),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).and_return(response)
    end

    it 'uses the supplied effective origin for follow-up requests', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      result = session.follow_up(
        url: 'https://redirected.example.com/news?page=2',
        relation: :pagination,
        origin_url: 'https://redirected.example.com/news'
      )

      expect(result).to eq(response)
      expect(Html2rss::RequestService).to have_received(:execute).with(
        satisfy do |follow_up_context|
          follow_up_context.origin_url.to_s == 'https://redirected.example.com/news' &&
            follow_up_context.url.to_s == 'https://redirected.example.com/news?page=2' &&
            follow_up_context.headers == context.headers
        end,
        strategy: :faraday
      )
      expect(logger).to have_received(:debug).with(
        %r{
          Html2rss::RequestSession:\s+relation=pagination\s+
          request_url=https://redirected\.example\.com/news\?page=2\s+
          final_url=https://redirected\.example\.com/news\?page=2\s+
          status=200\s+content_type="text/html"\s+bytes=13
        }x
      )
    end
  end

  describe '#effective_page_budget' do
    let(:policy) { Html2rss::RequestService::Policy.new(max_requests: 20) }
    let(:budget) { Html2rss::RequestService::Budget.new(max_requests: policy.max_requests) }

    it 'returns the requested budget when it fits the policy ceiling' do
      expect(session.effective_page_budget(3)).to eq(3)
    end

    it 'logs and clamps the configured budget when it exceeds the policy ceiling', :aggregate_failures do
      expect(session.effective_page_budget(20)).to eq(Html2rss::RequestService::Policy::MAX_REQUESTS_CEILING)
      expect(logger).to have_received(:warn).with(/pagination max_pages=20 exceeds system ceiling=10/)
    end
  end
end
