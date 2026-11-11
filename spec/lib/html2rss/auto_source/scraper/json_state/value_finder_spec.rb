# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Scraper::JsonState::ValueFinder do
  describe '.fetch' do
    it 'finds key directly in a hash' do
      expect(described_class.fetch({ title: 'Hello' }, %i[title name])).to eq('Hello')
    end

    it 'probes keys in order until one is present', :aggregate_failures do
      expect(described_class.fetch({ name: 'N' }, %i[title name])).to eq('N')
      expect(described_class.fetch({ name: 'N', title: 'T' }, %i[title name])).to eq('T')
    end

    it 'does not descend into nested wrapper hashes', :aggregate_failures do
      expect(described_class.fetch({ attributes: { name: 'World' } }, %i[title name])).to be_nil
      expect(described_class.fetch({ data: { title: 'Nested' } }, %i[title name])).to be_nil
    end

    it 'finds key inside array of objects' do
      array = [{ other: 'val' }, { title: 'Found in array' }]
      expect(described_class.fetch(array, %i[title name])).to eq('Found in array')
    end

    it 'returns nil when key is not found in array' do
      array = [{ other: 'val' }, { another: 'one' }]
      expect(described_class.fetch(array, %i[title name])).to be_nil
    end

    it 'returns nil for non-hash, non-array input' do
      expect(described_class.fetch('string', %i[title])).to be_nil
    end
  end
end
