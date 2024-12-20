# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService do
  specify(:aggregate_failures) do
    expect(described_class::UnknownStrategy).to be < Html2rss::Error
    expect(described_class::InvalidUrl).to be < Html2rss::Error
    expect(described_class::UnsupportedUrlScheme).to be < Html2rss::Error
  end

  describe '::STRATEGIES' do
    it do
      expect(described_class::STRATEGIES).to be_a(Hash)
    end
  end

  describe '#execute' do
    subject(:execute) { described_class.execute(ctx, strategy: strategy) }

    let(:strategy) { :faraday }
    let(:ctx) { instance_double(Html2rss::RequestService::Context) }

    let(:strategy_class) { described_class::STRATEGIES[strategy] }
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
end
