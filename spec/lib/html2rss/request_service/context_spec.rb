# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Context do
  describe '#initialize' do
    subject(:instance) { described_class.new(url:, headers:, request:, budget:) }

    let(:url) { 'http://www.example.com' }
    let(:headers) { {} }
    let(:request) { {} }
    let(:budget) { Html2rss::RequestService::Budget.new(max_requests: 1) }

    context 'with a valid URL (String)' do
      it 'does not raise an error' do
        expect { instance }.not_to raise_error
      end

      it 'creates a valid context', :aggregate_failures do
        expect(instance.url).to be_a(Html2rss::Url)
        expect(instance.url.to_s).to eq('http://www.example.com/')
        expect(instance.headers).to eq({})
      end
    end

    context 'with a valid URL (Html2rss::Url)' do
      let(:url) { Html2rss::Url.from_absolute('http://example.com') }

      it 'does not raise an error' do
        expect { instance }.not_to raise_error
      end

      it 'creates a valid context', :aggregate_failures do
        expect(instance.url).to be_a(Html2rss::Url)
        expect(instance.url.to_s).to eq(url.to_s)
      end
    end

    context 'with custom headers' do
      let(:headers) { { 'User-Agent': 'Custom Agent' } }

      it 'normalizes and freezes headers with string keys', :aggregate_failures do
        expect(instance.headers).to eq('User-Agent' => 'Custom Agent')
        expect(instance.headers).to be_frozen
      end
    end

    context 'with botasaurus request configuration' do
      let(:request) do
        {
          'botasaurus' => {
            'execution_mode' => 'browser'
          }
        }
      end
      let(:expected_request) do
        {
          botasaurus: {
            execution_mode: 'browser'
          }
        }
      end

      it 'exposes the request options' do
        expect(instance).to have_attributes(
          request: expected_request
        )
      end
    end

    context 'with defaults only' do
      it 'defaults to frozen empty headers and request, an initial relation and the default policy',
         :aggregate_failures do
        expect(instance).to have_attributes(headers: {}, request: {}, relation: :initial)
        expect(instance.headers).to be_frozen
        expect(instance.request).to be_frozen
        expect(instance.policy).to be_a(Html2rss::RequestService::Policy)
        expect(instance.budget).to equal(budget)
      end

      it 'uses the request url as its own origin' do
        expect(instance.origin_url).to eq(instance.url)
      end
    end

    context 'with a string origin url' do
      subject(:instance) { described_class.new(url:, budget:, origin_url: 'http://origin.example.com') }

      it 'normalizes it to an Html2rss::Url' do
        expect(instance.origin_url).to be_a(Html2rss::Url).and have_attributes(host: 'origin.example.com')
      end
    end

    context 'with an explicit relation' do
      subject(:instance) { described_class.new(url:, budget:, relation: :pagination) }

      it 'keeps the relation' do
        expect(instance.relation).to eq(:pagination)
      end
    end

    context 'with a request that has non-string keys' do
      let(:request) { { 1 => 'x' } }

      it 'names the request in the error' do
        expect { instance }.to raise_error(ArgumentError, 'request must use string or symbol keys (found 1)')
      end
    end

    context 'when policy is explicitly nil' do
      subject(:instance) { described_class.new(url:, policy: nil, budget:) }

      it 'raises an argument error' do
        expect { instance }.to raise_error(ArgumentError, 'policy must not be nil')
      end
    end

    context 'when budget is omitted' do
      subject(:instance) { described_class.new(url:) }

      it 'raises an argument error' do
        expect { instance }.to raise_error(ArgumentError, 'budget is required')
      end
    end

    context 'when budget is explicitly nil' do
      subject(:instance) { described_class.new(url:, budget: nil) }

      it 'raises an argument error' do
        expect { instance }.to raise_error(ArgumentError, 'budget must not be nil')
      end
    end
  end

  describe '#follow_up' do
    subject(:follow_up) { instance.follow_up(url: 'https://example.com/page/2', relation: :pagination) }

    let(:policy) { Html2rss::RequestService::Policy.new }
    let(:budget) { Html2rss::RequestService::Budget.new(max_requests: 2) }
    let(:instance) do
      described_class.new(
        url: 'https://example.com',
        headers: { 'User-Agent' => 'Custom Agent' },
        request: {
          botasaurus: {
            execution_mode: 'browser'
          }
        },
        policy:,
        budget:
      )
    end

    it 'shares origin, policy, budget, and request settings with the derived context', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(follow_up.origin_url).to eq(instance.origin_url)
      expect(follow_up.policy).to eq(policy)
      expect(follow_up.budget).to eq(budget)
      expect(follow_up.request).to eq(instance.request)
      expect(follow_up.relation).to eq(:pagination)
      expect(follow_up.headers).to eq(instance.headers)
    end

    context 'when an effective origin override is supplied' do
      subject(:follow_up) do
        instance.follow_up(
          url: 'https://redirected.example.com/page/2',
          relation: :pagination,
          origin_url: 'https://redirected.example.com/page/1'
        )
      end

      it 'uses the supplied origin url for follow-up policy checks' do
        expect(follow_up.origin_url.to_s).to eq('https://redirected.example.com/page/1')
      end
    end
  end
end
