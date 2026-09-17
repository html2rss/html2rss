# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::OptionContract do
  describe '.expectation_for' do
    it 'resolves extractor OPTIONS via symbol keys', :aggregate_failures do
      expect(described_class.expectation_for(parent: { extractor: 'attribute' }, leaf: :attribute))
        .to eq(type: 'string', required: true)
      expect(described_class.expectation_for(parent: { extractor: 'attribute' }, leaf: :missing))
        .to be_nil
    end

    it 'resolves post-processor OPTIONS via name (string keys included)', :aggregate_failures do
      expect(described_class.expectation_for(parent: { 'name' => 'gsub' }, leaf: :pattern))
        .to eq(type: 'string', required: true)
      expect(described_class.expectation_for(parent: { name: 'substring' }, leaf: :end))
        .to eq(type: 'integer', required: false)
    end

    it 'returns nil when parent has neither extractor nor post-processor name' do
      expect(described_class.expectation_for(parent: { selector: '.x' }, leaf: :attribute)).to be_nil
    end

    it 'returns nil for unknown registry names', :aggregate_failures do
      expect(described_class.expectation_for(parent: { extractor: 'nope' }, leaf: :attribute)).to be_nil
      expect(described_class.expectation_for(parent: { name: 'nope' }, leaf: :pattern)).to be_nil
    end
  end
end
