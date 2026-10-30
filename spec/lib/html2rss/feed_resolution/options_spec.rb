# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResolution::Options do
  describe '.from_auto_source' do
    it 'uses defaults when auto_source is nil or omits entry_resolution', :aggregate_failures do
      expect(described_class.from_auto_source(nil)).to have_attributes(enabled: true, max_probes: 5)
      expect(described_class.from_auto_source({})).to have_attributes(enabled: true, max_probes: 5)
    end

    it 'fills a partially specified entry_resolution with defaults', :aggregate_failures do
      expect(described_class.from_auto_source(entry_resolution: { max_probes: 2 }))
        .to have_attributes(enabled: true, max_probes: 2)
      expect(described_class.from_auto_source(entry_resolution: { enabled: false }))
        .to have_attributes(enabled: false, max_probes: 5)
    end

    it 'disables when enabled is false' do
      options = described_class.from_auto_source(entry_resolution: { enabled: false, max_probes: 1 })

      expect(options).to have_attributes(enabled: false, max_probes: 1)
    end
  end

  describe '#request_slots' do
    it 'adds the retry slot when enabled' do
      expect(described_class.new(enabled: true, max_probes: 5).request_slots).to eq(6)
    end

    it 'returns zero when disabled' do
      expect(described_class.new(enabled: false, max_probes: 5).request_slots).to eq(0)
    end

    it 'keeps a single retry when there are no probes' do
      expect(described_class.new(enabled: true, max_probes: 0).request_slots).to eq(1)
    end
  end
end
