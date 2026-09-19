# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::OptionSpec do
  describe '.expectation_for' do
    it 'resolves extractor OPTIONS as Ruby-typed expectations', :aggregate_failures do
      expect(described_class.expectation_for(parent: { extractor: 'attribute' }, leaf: :attribute))
        .to eq(type: String, required: true)
      expect(described_class.expectation_for(parent: { extractor: 'attribute' }, leaf: :missing))
        .to be_nil
    end

    it 'resolves post-processor OPTIONS via name (string keys included)', :aggregate_failures do
      expect(described_class.expectation_for(parent: { 'name' => 'gsub' }, leaf: :pattern))
        .to eq(type: String, required: true)
      expect(described_class.expectation_for(parent: { name: 'substring' }, leaf: :end))
        .to eq(type: Integer, required: false)
    end

    it 'returns nil when parent has neither extractor nor post-processor name' do
      expect(described_class.expectation_for(parent: { selector: '.x' }, leaf: :attribute)).to be_nil
    end

    it 'returns nil for unknown registry names', :aggregate_failures do
      expect(described_class.expectation_for(parent: { extractor: 'nope' }, leaf: :attribute)).to be_nil
      expect(described_class.expectation_for(parent: { name: 'nope' }, leaf: :pattern)).to be_nil
    end
  end

  describe '.option_for' do
    it 'resolves OptionSpec directly', :aggregate_failures do
      spec = described_class.option_for({ extractor: 'attribute' }, :attribute)
      expect(spec).to be_a(described_class)
      expect(spec.name).to eq(:attribute)
      expect(spec.json_type).to eq('string')
    end
  end

  describe '#valid_type?' do
    it 'validates single type options', :aggregate_failures do
      spec = described_class.new(name: :test, type: String)
      expect(spec.valid_type?('ok')).to be true
      expect(spec.valid_type?(123)).to be false
    end

    it 'validates multiple type options', :aggregate_failures do
      spec = described_class.new(name: :test, type: [String, Integer])
      expect(spec.valid_type?('ok')).to be true
      expect(spec.valid_type?(123)).to be true
      expect(spec.valid_type?(:symbol)).to be false
    end
  end

  describe '#error_message' do
    it 'formats type error messages with optional suffix', :aggregate_failures do
      required = described_class.new(name: :test, type: String, required: true)
      expect(required.error_message).to eq('`test` must be a string')

      optional = described_class.new(name: :test, type: Integer, required: false)
      expect(optional.error_message).to eq('`test` must be an integer or omitted')
    end
  end

  describe '.for' do
    it 'reads OPTIONS from the strategy class' do
      expect(described_class.for(Html2rss::Selectors::Extractors::Attribute).map(&:name))
        .to include(:attribute)
    end
  end
end
