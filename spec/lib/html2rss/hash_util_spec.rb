# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::HashUtil do
  describe '.deep_dup' do
    it 'duplicates nested hashes and arrays without sharing references' do
      source = { channel: { url: 'https://example.com' }, tags: %w[a b] }
      duplicate = described_class.deep_dup(source)

      duplicate[:channel][:url] = 'https://changed.example.com'
      duplicate[:tags] << 'c'

      expect(source).to eq(channel: { url: 'https://example.com' }, tags: %w[a b])
    end
  end

  describe '.deep_merge' do
    it 'recursively merges nested hashes while replacing scalar values' do
      merged = described_class.deep_merge(
        { channel: { title: 'Global', locale: 'en' }, retry: 1 },
        { channel: { title: 'Local' }, retry: 2 }
      )

      expect(merged).to eq(channel: { title: 'Local', locale: 'en' }, retry: 2)
    end
  end

  describe '.deep_symbolize_keys' do
    it 'converts nested string keys to symbols' do
      input = { 'request' => { 'browserless' => { 'preload' => { 'wait_after_ms' => 10 } } } }
      expected_output = { request: { browserless: { preload: { wait_after_ms: 10 } } } }
      expect(described_class.deep_symbolize_keys(input)).to eq(expected_output)
    end

    it 'raises on unsupported key types' do
      expect do
        described_class.deep_symbolize_keys({ 1 => 'invalid' })
      end.to raise_error(ArgumentError, /must use string or symbol keys/)
    end
  end

  describe '.assert_symbol_keys!' do
    it 'raises when a hash contains string keys' do
      expect do
        described_class.assert_symbol_keys!({ 'key' => 'value' })
      end.to raise_error(ArgumentError, /must use symbol keys/)
    end
  end

  describe '.assert_string_keys!' do
    it 'raises when a hash contains symbol keys' do
      expect do
        described_class.assert_string_keys!({ key: 'value' })
      end.to raise_error(ArgumentError, /must use string keys/)
    end
  end
end
