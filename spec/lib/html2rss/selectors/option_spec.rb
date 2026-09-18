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

  describe '.for' do
    it 'reads OPTIONS from the strategy class' do
      expect(described_class.for(Html2rss::Selectors::Extractors::Attribute).map(&:name))
        .to include(:attribute)
    end
  end
end
