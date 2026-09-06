# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedPipeline::StrategyPlan do
  describe '.resolve' do
    it 'resolves :auto to the Auto plan' do
      expect(described_class.resolve(:auto)).to eq(described_class::Auto.new)
    end

    it 'resolves a registered strategy to Concrete', :aggregate_failures do
      plan = described_class.resolve(:default)

      expect(plan).to be_a(described_class::Concrete)
      expect(plan.strategy).to eq(:default)
    end

    it 'accepts string names' do
      expect(described_class.resolve('botasaurus')).to eq(described_class::Concrete.new(strategy: :botasaurus))
    end

    it 'raises ArgumentError for an unknown plan' do
      expect { described_class.resolve(:unknown) }.to raise_error(ArgumentError, /unknown strategy plan/)
    end
  end

  describe '.concrete_for_diagnostic' do
    it 'collapses :auto to the default strategy' do
      expect(described_class.concrete_for_diagnostic(:auto)).to eq(:default)
    end

    it 'passes through concrete strategies and nil → auto', :aggregate_failures do
      expect(described_class.concrete_for_diagnostic(:botasaurus)).to eq(:botasaurus)
      expect(described_class.concrete_for_diagnostic(nil)).to eq(:default)
    end
  end

  describe '.valid?' do
    it 'accepts :auto and registered strategies', :aggregate_failures do
      expect(described_class.valid?(:auto)).to be true
      expect(described_class.valid?(:default)).to be true
      expect(described_class.valid?(:faraday)).to be true
      expect(described_class.valid?('botasaurus')).to be true
    end

    it 'rejects unknown names and non-names', :aggregate_failures do
      expect(described_class.valid?(:unknown)).to be false
      expect(described_class.valid?(nil)).to be false
      expect(described_class.valid?(123)).to be false
    end
  end

  describe '.accepted_names' do
    it 'lists :auto ahead of concrete transport strategies' do
      expect(described_class.accepted_names).to eq(
        [:auto, *Html2rss::RequestService.strategy_names.map(&:to_sym)].uniq
      )
    end
  end

  describe '#request_slots' do
    it 'returns the fallback retry budget size for Auto' do
      expect(described_class::Auto.new.request_slots).to eq(Html2rss::FeedPipeline::AutoFallback::CHAIN.size - 1)
    end

    it 'returns 0 for Concrete' do
      expect(described_class::Concrete.new(strategy: :default).request_slots).to eq(0)
    end
  end
end
