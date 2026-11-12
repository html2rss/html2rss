# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestSession do
  let(:logger) { instance_double(Logger, warn: nil, debug: nil) }

  describe '.build' do
    let(:config) do
      Html2rss::Config.from_hash(
        {
          strategy: :botasaurus,
          channel: { url: 'https://example.com/blog' },
          request: {},
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
          config:, strategy: :botasaurus, budget: resources.budget, policy: resources.policy, logger:
        )
      end

      before do
        allow(Html2rss::RequestService::Context).to receive(:new).and_call_original
        session
      end

      it { expect(session).to be_a(described_class) }
      it { expect(session.url.to_s).to eq('https://example.com/blog') }
      it { expect(session.max_requests).to eq(resources.policy.max_requests) }

      it 'wires config headers, request, policy, and budget into Context', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
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

      described_class.build(config:, strategy: :botasaurus, budget:, policy: resources.policy, logger:)

      expect(Html2rss::RequestService::Context).to have_received(:new).with(hash_including(budget:))
    end

    it 'prefers the scrape_url override over the configured channel url' do
      session = described_class.build(
        config:, strategy: :botasaurus, budget: resources.budget, policy: resources.policy,
        scrape_url: 'https://example.com/feed-source', logger:
      )

      expect(session.url.to_s).to eq('https://example.com/feed-source')
    end

    it 'hands the logger to the session for operational warnings', :aggregate_failures do
      session = described_class.build(
        config:, strategy: :botasaurus, budget: resources.budget, policy: resources.policy, logger:
      )
      session.effective_page_budget(1000)

      expect(logger).to have_received(:warn).with(/pagination max_pages=1000/)
    end

    it 'executes session requests with the strategy given to build', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      response = Html2rss::RequestService::Response.new(
        body: '<html></html>', url: Html2rss::Url.from_absolute('https://example.com/blog'),
        headers: { 'content-type' => 'text/html' }, status: 200
      )
      allow(Html2rss::RequestService).to receive(:execute).and_return(response)
      session = described_class.build(
        config:, strategy: :default, budget: resources.budget, policy: resources.policy, logger:
      )

      session.fetch_initial_response

      expect(Html2rss::RequestService).to have_received(:execute).with(anything, strategy: :default)
    end

    it 'falls back to Html2rss::Log when no logger is given' do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:warn)
      session = described_class.build(
        config:, strategy: :botasaurus, budget: resources.budget, policy: resources.policy
      )
      session.effective_page_budget(1000)

      expect(Html2rss::Log).to have_received(:warn).with(/pagination max_pages=1000/)
    end
  end

  describe '#fetch_initial_response' do
    let(:context) { request_session_context }
    let(:session) { described_class.new(context:, strategy: :default, logger:) }
    let(:redirected_response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/redirected'),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end

    before do
      allow(Html2rss::RequestService).to receive(:execute).with(context, strategy: :default).and_return(response)
    end

    it 'requests the initial page, tracks its url, and logs the response summary', :aggregate_failures do
      expect(session.fetch_initial_response).to eq(response)
      expect(session.visited?(response.url)).to be(true)
      expect(logger).to have_received(:debug).with(
        %r{Html2rss::RequestSession: relation=initial request_url=https://example\.com/news final_url=https://example\.com/news status=200 content_type="text/html" bytes=13}
      )
    end

    it 'tracks the final url after a redirect rather than the requested url', :aggregate_failures do
      redirected = redirected_response
      allow(Html2rss::RequestService).to receive(:execute).with(context, strategy: :default).and_return(redirected)

      session.fetch_initial_response

      expect(session.visited?('https://example.com/redirected')).to be(true)
      expect(session.visited?('https://example.com/news')).to be(false)
    end
  end

  describe '#follow_up' do
    subject(:result) do
      session.follow_up(
        url: 'https://redirected.example.com/news?page=2',
        relation: :pagination,
        origin_url: 'https://redirected.example.com/news'
      )
    end

    let(:context) { request_session_context }
    let(:session) { described_class.new(context:, strategy: :default, logger:) }
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

    it { is_expected.to eq(response) }

    it 'executes with pagination context', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      result
      expect(Html2rss::RequestService).to have_received(:execute).with(
        satisfy do |c|
          c.origin_url.to_s == 'https://redirected.example.com/news' &&
            c.url.to_s == 'https://redirected.example.com/news?page=2' &&
            c.headers == context.headers
        end,
        strategy: :default
      )
    end

    it 'logs the follow-up request' do
      result
      expect(logger).to have_received(:debug).with(
        %r{relation=pagination.*request_url=https://redirected\.example\.com/news\?page=2}
      )
    end

    it 'tracks the final url of the follow-up response as visited', :aggregate_failures do
      result
      expect(session.visited?('https://redirected.example.com/news?page=2')).to be(true)
      expect(session.visited?('https://example.com/news')).to be(false)
    end

    context 'with a feed the page advertises on another host (real policy and budget)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:page_url) { Html2rss::Url.from_absolute('https://example.com/news') }
      let(:feed_url) { Html2rss::Url.from_absolute('https://feeds.example.net/show.xml') }
      let(:resolver) { instance_double(Resolv) }
      let(:policy) { Html2rss::RequestService::Policy.new(max_requests: 2, resolver:) }
      let(:budget) { Html2rss::RequestService::Budget.new(max_requests: 2) }
      let(:context) { Html2rss::RequestService::Context.new(url: page_url, policy:, budget:) }
      let(:advertisement) do
        Html2rss::RequestService::FeedAdvertisement.from_document(
          Nokogiri::HTML('<head><link rel="alternate" type="application/rss+xml" href="http://feeds.example.net/show.xml"></head>'),
          page_url:
        )
      end
      let(:feed_body) { '<rss version="2.0"><channel></channel></rss>' }

      before do
        allow(Html2rss::RequestService).to receive(:execute).and_call_original
        allow(resolver).to receive(:each_address) do |host, &block|
          block.call(host.start_with?('internal.') ? '10.0.0.9' : '93.184.216.34')
        end
        stub_request(:get, page_url.to_s).to_return(status: 200, body: '<html></html>',
                                                    headers: { 'Content-Type' => 'text/html' })
        stub_request(:get, feed_url.to_s).to_return(status: 200, body: feed_body,
                                                    headers: { 'Content-Type' => 'application/rss+xml' })
      end

      it 'fetches the advertised feed over https from one request slot', :aggregate_failures do
        session.fetch_initial_response

        response = session.follow_up(url: feed_url, relation: :advertised_feed, origin_url: page_url, advertisement:)

        expect(response.body).to eq(feed_body)
        expect(budget.remaining_requests).to eq(0)
        expect(a_request(:get, 'http://feeds.example.net/show.xml')).not_to have_been_made
      end

      it 'respects the request budget' do
        session.fetch_initial_response
        session.follow_up(url: feed_url, relation: :advertised_feed, origin_url: page_url, advertisement:)

        expect { session.follow_up(url: feed_url, relation: :advertised_feed, origin_url: page_url, advertisement:) }
          .to raise_error(Html2rss::RequestService::RequestBudgetExceeded)
      end

      it 'denies a non-advertised URL on the same feed host' do
        expect do
          session.follow_up(url: 'https://feeds.example.net/other.xml', relation: :advertised_feed,
                            origin_url: page_url, advertisement:)
        end.to raise_error(Html2rss::RequestService::CrossOriginFollowUpDenied)
      end

      it 'denies a redirect from the advertised feed to a private address', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- redirect stub + assertions
        stub_request(:get, feed_url.to_s).to_return(status: 302,
                                                    headers: { 'Location' => 'https://internal.example.net/x' })
        internal = stub_request(:get, 'https://internal.example.net/x')

        expect { session.follow_up(url: feed_url, relation: :advertised_feed, origin_url: page_url, advertisement:) }
          .to raise_error(Html2rss::RequestService::PrivateNetworkDenied)
        expect(internal).not_to have_been_requested
      end

      it 'follows a redirect from the advertised feed to another public https host' do
        stub_request(:get, feed_url.to_s).to_return(status: 301,
                                                    headers: { 'Location' => 'https://cdn.example.net/show.xml' })
        stub_request(:get, 'https://cdn.example.net/show.xml').to_return(status: 200, body: feed_body)

        response = session.follow_up(url: feed_url, relation: :advertised_feed, origin_url: page_url, advertisement:)

        expect(response.url.to_s).to eq('https://cdn.example.net/show.xml')
      end
    end
  end

  describe '#effective_page_budget' do
    let(:context) { request_session_context(max_requests: 20) }
    let(:session) { described_class.new(context:, strategy: :default, logger:) }

    it 'returns the requested budget without logging when it fits the policy ceiling', :aggregate_failures do
      expect(session.effective_page_budget(3)).to eq(3)
      expect(logger).not_to have_received(:warn)
    end

    it 'logs and clamps the configured budget when it exceeds the policy ceiling', :aggregate_failures do
      expect(session.effective_page_budget(20)).to eq(Html2rss::RequestService::Policy::MAX_REQUESTS_CEILING)
      expect(logger).to have_received(:warn).with(/pagination max_pages=20 exceeds system ceiling=10/)
    end

    it 'falls back to Html2rss::Log when constructed without a logger' do
      allow(Html2rss::Log).to receive(:warn)
      described_class.new(context:, strategy: :default).effective_page_budget(20)

      expect(Html2rss::Log).to have_received(:warn).with(/pagination max_pages=20 exceeds system ceiling=10/)
    end
  end

  describe '#remember! and #visited?' do
    let(:session) { described_class.new(context: request_session_context, strategy: :default, logger:) }

    it 'matches urls by their normalized form', :aggregate_failures do
      session.remember!('HTTP://Example.COM/news')

      expect(session.visited?('http://example.com/news')).to be(true)
      expect(session.visited?('http://example.com/other')).to be(false)
    end

    it 'rejects relative urls' do
      expect { session.remember!('/news') }.to raise_error(Html2rss::Url::InvalidUrlError)
    end
  end

  describe '#page_responses' do
    let(:context) { request_session_context }
    let(:session) { described_class.new(context:, strategy: :default, logger:) }
    let(:initial_response) do
      Html2rss::RequestService::Response.new(
        body: '<html></html>',
        url: Html2rss::Url.from_absolute('https://example.com/news'),
        headers: { 'content-type' => 'text/html' },
        status: 200
      )
    end
    let(:pagination_config) { { max_pages: 2 } }

    it 'returns array with initial response only when pagination config is absent' do
      expect(session.page_responses(initial_response)).to eq([initial_response])
    end

    it 'delegates to Pager.for with self as session when pagination config is present', :aggregate_failures do
      allow(Html2rss::RequestSession::Pager).to receive(:for).and_return([initial_response])

      expect(session.page_responses(initial_response, pagination_config:)).to eq([initial_response])
      expect(Html2rss::RequestSession::Pager).to have_received(:for).with(
        pagination_config, session:, initial_response:
      )
    end
  end
end
