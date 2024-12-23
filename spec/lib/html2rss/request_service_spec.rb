# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService do
  specify(:aggregate_failures) do
    expect(described_class::UnknownStrategy).to be < Html2rss::Error
    expect(described_class::InvalidUrl).to be < Html2rss::Error
    expect(described_class::UnsupportedUrlScheme).to be < Html2rss::Error
  end

  describe '.default_strategy_name' do
    specify(:aggregate_failures) do
      expect(described_class.default_strategy_name).to be :faraday
      expect(described_class.strategy_registered?(:faraday)).to be true
    end
  end

  describe '#execute' do
    subject(:execute) { described_class.execute(ctx, strategy: strategy) }

    let(:strategy) { :faraday }
    let(:ctx) { instance_double(Html2rss::RequestService::Context) }

    let(:strategy_class) { described_class::FaradayStrategy }
    let(:strategy_instance) do
      instance_double strategy_class, execute: nil
    end

    context 'with a known strategy' do
      it do
        allow(strategy_class).to receive(:new).with(ctx).and_return(strategy_instance)
        execute
        expect(strategy_class).to have_received(:new).with(ctx)
      end
    end

    context 'with an unknown strategy' do
      let(:strategy) { :unknown }

      it do
        expect { execute }.to raise_error(Html2rss::RequestService::UnknownStrategy)
      end
    end
  end

  describe '.register_strategy' do
    let(:new_strategy) { Class.new }
    let(:strategy_name) { :new_strategy }

    it 'registers a new strategy' do
      expect do
        described_class.register_strategy(strategy_name, new_strategy)
      end.to change { described_class.strategy_registered?(strategy_name) }.from(false).to(true)
    end

    it 'raises an error if the strategy class is not a class' do
      expect { described_class.register_strategy(strategy_name, 'not a class') }.to raise_error(ArgumentError)
    end
  end

  describe '.strategy_registered?' do
    context 'when the strategy is registered' do
      it 'returns true' do
        expect(described_class.strategy_registered?(:faraday)).to be true
      end
    end

    context 'when the strategy is not registered' do
      it 'returns false' do
        expect(described_class.strategy_registered?(:unknown)).to be false
      end
    end

    context 'when the strategy name is a string' do
      it 'returns true for a registered strategy' do
        expect(described_class.strategy_registered?('faraday')).to be true
      end

      it 'returns false for an unregistered strategy' do
        expect(described_class.strategy_registered?('unknown')).to be false
      end
    end
  end

  describe '.default_strategy_name=' do
    after do
      described_class.default_strategy_name = :faraday
    end

    context 'when the strategy is registered' do
      it 'sets the default strategy' do
        described_class.default_strategy_name = :browserless
        expect(described_class.default_strategy_name).to be :browserless
      end
    end

    context 'when the strategy is not registered' do
      it 'raises an UnknownStrategy error' do
        expect do
          described_class.default_strategy_name = :unknown
        end.to raise_error(Html2rss::RequestService::UnknownStrategy)
      end
    end
  end

  describe '.unregister_strategy' do
    context 'when the strategy is registered' do
      before { described_class.register_strategy(:foobar, Class) }

      let(:strategy_name) { :foobar }

      it 'unregisters the strategy' do
        expect do
          described_class.unregister_strategy(strategy_name)
        end.to change { described_class.strategy_registered?(strategy_name) }.from(true).to(false)
      end
    end

    context 'when the strategy is not registered' do
      let(:strategy_name) { :unknown }

      it 'returns false' do
        expect(described_class.unregister_strategy(strategy_name)).to be false
      end
    end

    context 'when trying to unregister the default strategy' do
      it 'raises an ArgumentError' do
        expect do
          described_class.unregister_strategy(described_class.default_strategy_name)
        end.to raise_error(ArgumentError, 'Cannot unregister the default strategy')
      end
    end
  end
end
