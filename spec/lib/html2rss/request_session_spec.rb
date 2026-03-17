# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession do
  subject(:session) { described_class.new(context:, strategy:, logger:) }

  let(:strategy) { :faraday }
  let(:logger) { instance_double(Logger, warn: nil) }
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

  describe '#fetch_initial_response' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).with(context, strategy:).and_return(response)
    end

    it 'requests the initial page and tracks its url', :aggregate_failures do
      expect(session.fetch_initial_response).to eq(response)
      expect(session.visited?(response.url)).to be(true)
    end
  end

  describe '#follow_up' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://redirected.example.com/news?page=2'),
        headers: { 'content-type' => 'text/html' }
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
