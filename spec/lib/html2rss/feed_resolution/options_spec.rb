# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Options do
  describe '.from_auto_source' do
    it 'uses defaults when auto_source is not a Hash' do
      expect(described_class.from_auto_source('no')).to have_attributes(enabled: true, max_probes: 5)
    end

    it 'uses defaults when entry_resolution is omitted' do
      expect(described_class.from_auto_source({})).to have_attributes(enabled: true, max_probes: 5)
    end

    it 'uses defaults when entry_resolution is not a Hash' do
      options = described_class.from_auto_source(entry_resolution: 'no')

      expect(options).to have_attributes(enabled: true, max_probes: 5)
    end

    it 'treats enabled nil as on and coerces max_probes' do
      options = described_class.from_auto_source(entry_resolution: { enabled: nil, max_probes: '2' })

      expect(options).to have_attributes(enabled: true, max_probes: 2)
    end

    it 'disables when enabled is false' do
      options = described_class.from_auto_source(entry_resolution: { enabled: false, max_probes: 1 })

      expect(options).to have_attributes(enabled: false, max_probes: 1)
    end

    it 'reads a Hash subclass' do
      auto_source = Class.new(Hash).new
      auto_source[:entry_resolution] = { enabled: false, max_probes: 4 }

      expect(described_class.from_auto_source(auto_source)).to have_attributes(enabled: false, max_probes: 4)
    end

    it 'reads entry_resolution from a Hash subclass' do
      raw = Class.new(Hash).new
      raw[:enabled] = false
      raw[:max_probes] = 3

      expect(described_class.from_auto_source(entry_resolution: raw)).to have_attributes(enabled: false, max_probes: 3)
    end

    it 'raises when max_probes is not an integer' do
      expect do
        described_class.from_auto_source(entry_resolution: { max_probes: 'no' })
      end.to raise_error(ArgumentError)
    end
  end
end
