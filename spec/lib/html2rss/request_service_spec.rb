# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Html2rss::RequestService do
  let(:error_types) do
    [
      described_class::UnknownStrategy,
      described_class::InvalidUrl,
      described_class::UnsupportedUrlScheme,
      described_class::RequestBudgetExceeded,
      described_class::PrivateNetworkDenied,
      described_class::CrossOriginFollowUpDenied,
      described_class::ResponseTooLarge,
      described_class::RequestTimedOut,
      described_class::ConnectionFailed,
      described_class::BotasaurusConfigurationError,
      described_class::BotasaurusConnectionFailed,
      described_class::BotasaurusServiceError
    ]
  end

  describe 'error types' do
    specify(:aggregate_failures) do
      expect(error_types).to all(be < Html2rss::Error)
    end
  end

  describe 'RequestTimedOut' do
    it 'exposes optional timeout_phase', :aggregate_failures do
      timed_out = described_class::RequestTimedOut.new('timed out', timeout_phase: 'work')
      transport = described_class::RequestTimedOut.new('timed out')

      expect(timed_out.timeout_phase).to eq('work')
      expect(timed_out.message).to eq('timed out')
      expect(transport.timeout_phase).to be_nil
    end
  end

  describe '.default_strategy_name' do
    # rubocop:disable-next RSpec/ExampleLength -- registered strategy + migration alias matrix
    specify(:aggregate_failures) do
      expect(described_class.default_strategy_name).to be :default
      expect(described_class.strategy_registered?(:default)).to be true
      expect(described_class.strategy_registered?(:httpx)).to be true
      expect(described_class.strategy_registered?(:faraday)).to be true
      expect(described_class.strategy_registered?(:botasaurus)).to be true
      expect(described_class.strategy_registered?(:browserless)).to be true
    end
  end

  describe '#execute' do
    subject(:execute) { described_class.execute(ctx, strategy:) }

    let(:strategy) { :default }
    let(:ctx) do
      instance_double(
        Html2rss::RequestService::Context,
        relation: :initial,
        url: instance_double(Html2rss::Url, host: 'example.com')
      )
    end
    let(:strategy_class) { described_class::HttpxStrategy }
    let(:strategy_instance) { instance_double(strategy_class, execute: nil) }

    context 'with a known strategy' do
      it do
        allow(strategy_class).to receive(:new).with(ctx).and_return(strategy_instance)
        execute
        expect(strategy_class).to have_received(:new).with(ctx)
      end
    end

    context 'with a silent strategy alias' do
      let(:strategy) { :httpx }

      it 'delegates to HttpxStrategy without warnings', :aggregate_failures do
        allow(strategy_class).to receive(:new).with(ctx).and_return(strategy_instance)
        allow(Html2rss::Log).to receive(:warn)

        execute

        expect(strategy_class).to have_received(:new).with(ctx)
        expect(Html2rss::Log).not_to have_received(:warn)
      end
    end

    context 'with a deprecated migration strategy alias' do
      let(:strategy) { :faraday }

      # rubocop:disable-next RSpec/ExampleLength -- asserts structured strategy_deprecated JSON fields
      it 'emits structured strategy_deprecated and delegates to HttpxStrategy', :aggregate_failures do
        allow(strategy_class).to receive(:new).with(ctx).and_return(strategy_instance)
        allow(Html2rss::Log).to receive(:warn)

        execute

        expect(strategy_class).to have_received(:new).with(ctx)
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          expect(JSON.parse(payload)).to include(
            'event_name' => 'strategy_deprecated',
            'strategy' => 'faraday',
            'replacement' => 'default',
            'host' => 'example.com',
            'message' => a_string_including('strategy=:faraday', 'using :default')
          )
        end
      end
    end

    context 'with a deprecated browserless strategy alias' do
      let(:strategy) { :browserless }
      let(:strategy_class) { described_class::BotasaurusStrategy }

      # rubocop:disable-next RSpec/ExampleLength -- asserts structured strategy_deprecated JSON fields
      it 'emits structured strategy_deprecated and delegates to BotasaurusStrategy', :aggregate_failures do
        allow(strategy_class).to receive(:new).with(ctx).and_return(strategy_instance)
        allow(Html2rss::Log).to receive(:warn)

        execute

        expect(strategy_class).to have_received(:new).with(ctx)
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          expect(JSON.parse(payload)).to include(
            'event_name' => 'strategy_deprecated',
            'strategy' => 'browserless',
            'replacement' => 'botasaurus',
            'host' => 'example.com',
            'message' => a_string_including('strategy=:browserless', 'using :botasaurus')
          )
        end
      end
    end

    context 'when a follow-up context uses a deprecated strategy' do
      # rubocop:disable-next RSpec/ExampleLength -- builds initial+follow_up contexts to assert once-per-session
      it 'does not re-emit strategy_deprecated', :aggregate_failures do
        budget = described_class::Budget.new(max_requests: 2)
        initial = described_class::Context.new(url: 'https://example.com/news', budget:)
        follow_up = initial.follow_up(url: 'https://example.com/news?page=2', relation: :pagination)
        allow(described_class::HttpxStrategy).to receive(:new).and_return(strategy_instance)
        allow(Html2rss::Log).to receive(:warn)

        described_class.execute(initial, strategy: :faraday)
        described_class.execute(follow_up, strategy: :faraday)

        expect(Html2rss::Log).to have_received(:warn).once
      end
    end

    context 'with an unknown strategy' do
      let(:strategy) { :unknown }

      it do
        expect { execute }.to raise_error(Html2rss::RequestService::UnknownStrategy)
      end
    end
  end

  describe '.strategy_registered?' do
    context 'when the strategy is registered' do
      it 'returns true' do
        expect(described_class.strategy_registered?(:default)).to be true
      end
    end

    context 'when the strategy is not registered' do
      it 'returns false' do
        expect(described_class.strategy_registered?(:unknown)).to be false
      end
    end

    context 'when the strategy name is a string' do
      it 'returns true for a registered strategy' do
        expect(described_class.strategy_registered?('default')).to be true
      end

      it 'returns false for an unregistered strategy' do
        expect(described_class.strategy_registered?('unknown')).to be false
      end
    end
  end
end
