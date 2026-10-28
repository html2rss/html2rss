# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::HashUtil do
  describe '.deep_dup' do
    it 'duplicates nested hashes and arrays without sharing references' do
      source = { channel: { url: 'https://example.com' }, tags: [{ name: 'a' }] }
      duplicate = described_class.deep_dup(source)

      duplicate[:channel][:url] = 'https://changed.example.com'
      duplicate[:tags][0][:name] = 'c'

      expect(source).to eq(channel: { url: 'https://example.com' }, tags: [{ name: 'a' }])
    end

    it 'returns a mutable copy of a string', :aggregate_failures do
      source = 'https://example.com'
      duplicate = described_class.deep_dup(source)
      expect(duplicate).to eq(source)
      expect(duplicate).not_to be(source)
      expect(duplicate).not_to be_frozen
    end

    it 'returns the same immediate' do
      expect(described_class.deep_dup(1)).to be(1)
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
      input = { 'request' => { 'botasaurus' => { 'execution_mode' => 'browser' } } }
      expected_output = { request: { botasaurus: { execution_mode: 'browser' } } }
      expect(described_class.deep_symbolize_keys(input)).to eq(expected_output)
    end

    it 'symbolizes string keys inside arrays' do
      input = [{ 'channel' => 'title' }, 'plain']

      expect(described_class.deep_symbolize_keys(input)).to eq([{ channel: 'title' }, 'plain'])
    end

    it 'keeps symbol keys' do
      expect(described_class.deep_symbolize_keys({ request: 'ok' })).to eq(request: 'ok')
    end

    it 'raises on unsupported key types' do
      expect { described_class.deep_symbolize_keys({ /bad/ => 'invalid' }) }
        .to raise_error(ArgumentError, 'hash must use string or symbol keys (found /bad/)')
    end

    it 'reports the caller context for a nested invalid key' do
      input = { 'outer' => { /bad/ => 'invalid' } }

      expect { described_class.deep_symbolize_keys(input, context: 'config') }
        .to raise_error(ArgumentError, 'config must use string or symbol keys (found /bad/)')
    end
  end

  describe '.deep_stringify_keys' do
    it 'converts nested symbol keys and symbol values to strings' do
      input = { channel: { url: 'https://example.com' }, strategy: :default }
      expected = { 'channel' => { 'url' => 'https://example.com' }, 'strategy' => 'default' }

      expect(described_class.deep_stringify_keys(input)).to eq(expected)
    end

    it 'stringifies keys and symbol values inside arrays' do
      input = [{ channel: :title }, :default]

      expect(described_class.deep_stringify_keys(input)).to eq([{ 'channel' => 'title' }, 'default'])
    end
  end

  describe '.assert_symbol_keys!' do
    it 'returns nil for a non-hash' do
      expect(described_class.assert_symbol_keys!('nope')).to be_nil
    end

    it 'accepts nested symbol keys' do
      hash = { key: 'value', nested: { ok: 1 } }

      expect(described_class.assert_symbol_keys!(hash)).to be(hash)
    end

    it 'raises when a hash contains string keys' do
      hash = { ok: 1, 'bad' => 2, also: 3 }

      expect { described_class.assert_symbol_keys!(hash) }
        .to raise_error(ArgumentError, 'hash must use symbol keys (found "bad")')
    end

    it 'rejects nested string keys' do
      expect { described_class.assert_symbol_keys!({ outer: { 'bad' => 1 } }) }
        .to raise_error(ArgumentError, 'hash must use symbol keys (found "bad")')
    end

    it 'does not walk nested hashes when deep is false' do
      hash = { outer: { 'bad' => 1 } }

      expect(described_class.assert_symbol_keys!(hash, deep: false)).to be_nil
    end
  end

  describe '.assert_string_keys!' do
    it 'returns nil for a non-hash' do
      expect(described_class.assert_string_keys!(:nope)).to be_nil
    end

    it 'accepts nested string keys' do
      hash = { 'key' => :value, 'nested' => { 'ok' => 1 } }

      expect(described_class.assert_string_keys!(hash)).to be(hash)
    end

    it 'raises when a hash contains symbol keys' do
      hash = { 'ok' => 1, bad: 2, 'also' => 3 }

      expect { described_class.assert_string_keys!(hash) }
        .to raise_error(ArgumentError, 'hash must use string keys (found :bad)')
    end

    it 'rejects nested symbol keys' do
      expect { described_class.assert_string_keys!({ 'outer' => { bad: 1 } }) }
        .to raise_error(ArgumentError, 'hash must use string keys (found :bad)')
    end

    it 'does not walk nested hashes when deep is false' do
      hash = { 'outer' => { bad: 1 } }

      expect(described_class.assert_string_keys!(hash, deep: false)).to be_nil
    end
  end
end
