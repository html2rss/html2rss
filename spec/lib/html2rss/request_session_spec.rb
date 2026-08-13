# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession do
  subject(:session) { described_class.new(context:, strategy:, logger:) }

  def strategy
    :faraday
  end

  def logger
    @logger ||= instance_double(Logger, warn: nil, debug: nil)
  end

  def policy
    @policy ||= Html2rss::RequestService::Policy.new(max_requests: 3)
  end

  def budget
    @budget ||= Html2rss::RequestService::Budget.new(max_requests: 3)
  end

  def context
    @context ||= Html2rss::RequestService::Context.new(
      url: 'https://example.com/news',
      headers: { 'User-Agent' => 'RSpec' },
      policy:,
      budget:
    )
  end

  def pagination_context?(ctx)
    ctx.origin_url.to_s == 'https://redirected.example.com/news' &&
      ctx.url.to_s == 'https://redirected.example.com/news?page=2' &&
      ctx.headers == context.headers
  end

  describe '.build' do
    let(:config) do
      Html2rss::Config.from_hash(
        {
          strategy: :browserless,
          channel: { url: 'https://example.com/blog' },
          request: { browserless: { preload: { wait_after_ms: 500 } } },
          selectors: {
            items: { selector: 'article' },
            title: { selector: 'h2' }
          }
        }
      )
    end
    let(:resources) { Html2rss::FeedPipeline::RuntimePolicy.resources_for(config) }

    context 'when building context once from config' do
      let(:session) do
        described_class.build(
          config:, strategy: :browserless, budget: resources.budget, policy: resources.policy, logger:
        )
      end

      before do
        allow(Html2rss::RequestService::Context).to receive(:new).and_call_original
        session
      end

      it { expect(session).to be_a(described_class) }
      it { expect(session.url.to_s).to eq('https://example.com/blog') }
      it { expect(session.max_requests).to eq(resources.policy.max_requests) }

      it 'wires config headers, request, policy, and budget into Context', :aggregate_failures do
        expect(Html2rss::RequestService::Context).to have_received(:new).with(
          hash_including(
            headers: config.headers,
            request: config.request,
            policy: resources.policy,
            budget: resources.budget
          )
        )
      end
    end

    it 'uses the provided budget object for the session context' do
      budget = Html2rss::RequestService::Budget.new(max_requests: 2)
      allow(Html2rss::RequestService::Context).to receive(:new).and_call_original

      described_class.build(config:, strategy: :browserless, budget:, policy: resources.policy, logger:)

      expect(Html2rss::RequestService::Context).to have_received(:new).with(hash_including(budget:))
    end
  end

  describe '#fetch_initial_response' do
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

  describe '#follow_up' do
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

    context 'with pagination follow-up' do
      subject(:result) do
        session.follow_up(
          url: 'https://redirected.example.com/news?page=2',
          relation: :pagination,
          origin_url: 'https://redirected.example.com/news'
        )
      end

      it { is_expected.to eq(response) }

      it 'executes with pagination context' do
        result
        expect(Html2rss::RequestService).to have_received(:execute).with(
          satisfy { |c| pagination_context?(c) }, strategy: :faraday
        )
      end

      it 'logs the follow-up request' do
        result
        expect(logger).to have_received(:debug).with(
          %r{relation=pagination.*request_url=https://redirected\.example\.com/news\?page=2}
        )
      end
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

  describe '#page_responses' do
    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end

    context 'without pagination config' do
      it 'returns array with initial response only' do
        expect(session.page_responses(initial_response)).to eq([initial_response])
      end
    end

    context 'with pagination config' do
      let(:pagination_config) { { max_pages: 2 } }

      before do
        allow(Html2rss::RequestSession::Pager).to receive(:for).and_return([initial_response])
      end

      it 'delegates to Pager.for with self as session', :aggregate_failures do
        expect(session.page_responses(initial_response, pagination_config:)).to eq([initial_response])
        expect(Html2rss::RequestSession::Pager).to have_received(:for).with(
          pagination_config, session:, initial_response:
        )
      end
    end
  end
end
