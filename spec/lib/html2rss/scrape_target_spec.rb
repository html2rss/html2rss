# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::ScrapeTarget do
  describe '.from_config' do
    it 'copies the config URL onto entry and effective' do
      entry = 'https://entry.example/a'
      target = described_class.from_config(Data.define(:url).new(entry))

      expect([target.entry_url, target.effective_url]).to eq([entry, entry])
    end
  end

  describe '#with_effective' do
    it 'keeps the entry URL and stores the normalized effective URL' do
      entry = 'https://entry.example/a'
      updated = described_class.new(entry_url: entry, effective_url: entry)
                               .with_effective('  HTTPS://Effective.EXAMPLE/b  ')

      expect([updated.entry_url, updated.effective_url]).to eq([entry, 'https://effective.example/b'])
    end
  end
end
