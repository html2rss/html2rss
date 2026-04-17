# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Context do
  describe '#initialize' do
    subject(:instance) { described_class.new(url:, headers:, request:) }

    let(:url) { 'http://www.example.com' }
    let(:headers) { {} }
    let(:request) { {} }

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

    context 'with browserless request configuration' do
      let(:request) do
        {
          'browserless' => {
            'preload' => {
              'click_selectors' => [{ 'selector' => '.load-more', 'max_clicks' => 2 }]
            }
          }
        }
      end
      let(:expected_request) do
        {
          browserless: {
            preload: {
              click_selectors: [{ selector: '.load-more', max_clicks: 2 }]
            }
          }
        }
      end

      it 'exposes the request options' do
        expect(instance).to have_attributes(
          request: expected_request,
          browserless: expected_request[:browserless],
          browserless_preload: expected_request.dig(:browserless, :preload)
        )
      end
    end

    context 'when policy is explicitly nil' do
      subject(:instance) { described_class.new(url:, policy: nil) }

      it 'raises an argument error' do
        expect { instance }.to raise_error(ArgumentError, 'policy must not be nil')
      end
    end

    context 'when budget is explicitly nil' do
      subject(:instance) { described_class.new(url:, budget: nil) }

      it 'raises an argument error' do
        expect { instance }.to raise_error(ArgumentError, 'budget must not be nil')
      end
    end

    context 'when selected_strategy is auto' do
      subject(:instance) { described_class.new(url:, selected_strategy: :auto) }

      it 'raises an argument error' do
        expect { instance }.to raise_error(ArgumentError, 'selected_strategy must be a concrete strategy')
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
          browserless: {
            preload: {
              scroll_down: { iterations: 2 }
            }
          }
        },
        policy:,
        budget:,
        selected_strategy: :botasaurus
      )
    end

    it 'shares origin, policy, budget, and request settings with the derived context', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(follow_up.origin_url).to eq(instance.origin_url)
      expect(follow_up.policy).to eq(policy)
      expect(follow_up.budget).to eq(budget)
      expect(follow_up.request).to eq(instance.request)
      expect(follow_up.relation).to eq(:pagination)
      expect(follow_up.headers).to eq(instance.headers)
      expect(follow_up.selected_strategy).to eq(:botasaurus)
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
