# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::Manifest do
  describe '.canonical_bytes_for' do
    it 'deep-sorts keys for deterministic signing bytes' do
      bytes = described_class.canonical_bytes_for(b: 1, a: { z: 2, m: 3 })
      expect(bytes).to eq('{"a":{"m":3,"z":2},"b":1}')
    end
  end

  describe '.build' do
    subject(:manifest) do
      bundle_dir = RegistryTestSupport::VALID_BUNDLE
      relative_paths = RegistryTestSupport.manifest_relative_paths(bundle_dir)
      file_index = described_class.file_index(bundle_dir, relative_paths)
      described_class.build(
        file_index:,
        registry_id: 'test',
        version: '1.0.0',
        public_key_id: RegistryTestSupport::TEST_KEY_ID
      )
    end

    it 'emits registry.v1 metadata and file digests', :aggregate_failures do
      expect(manifest.registry_id).to eq('test')
      expect(manifest.files.keys).to all(start_with('configs/'))
      expect(manifest.canonical_bytes).to eq(described_class.canonical_bytes_for(manifest.to_h))
    end
  end

  describe '.parse' do
    it 'round-trips canonical bytes' do
      with_copied_valid_bundle do |bundle_dir|
        manifest = build_fixture_manifest(bundle_dir:)
        write_manifest!(bundle_dir, manifest)

        parsed = described_class.parse(File.read(File.join(bundle_dir, described_class::MANIFEST_FILE)))
        expect(parsed.canonical_bytes).to eq(manifest.canonical_bytes)
      end
    end

    it 'rejects manifest paths that escape configs/' do
      payload = build_fixture_manifest.to_h.merge(files: { 'configs/../evil.yml' => 'a' * 64 })

      expect do
        described_class.parse(JSON.generate(payload))
      end.to raise_error(Html2rss::Registry::ManifestError, /Path traversal/)
    end
  end

  describe '.normalize_version' do
    it 'strips leading v' do
      expect(described_class.normalize_version('v2026.08.23')).to eq('2026.08.23')
    end
  end

  describe '.compare_versions' do
    it 'compares semantic/calendar versions numerically', :aggregate_failures do
      expect(described_class.compare_versions('v2026.08.22', '2026.08.21')).to eq(1)
      expect(described_class.compare_versions('2026.08.21', '2026.08.22')).to eq(-1)
      expect(described_class.compare_versions('1.0.0', '1.0.0')).to eq(0)
    end
  end

  describe '.exceeds_max?' do
    [
      ['2026.08.22', '2026.08.21', true],
      ['2026.08.21', '2026.08.22', false],
      ['v2026.08.22', '2026.08.21', true],
      ['2026.08.22', nil, false]
    ].each do |manifest_version, max_version, expected|
      it "returns #{expected} for #{manifest_version} vs #{max_version.inspect}" do
        expect(described_class.exceeds_max?(manifest_version, max_version)).to be(expected)
      end
    end
  end
end
