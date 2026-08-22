# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::Manifest do
  let(:bundle_dir) { RegistryTestSupport::VALID_BUNDLE }

  describe '.build' do
    subject(:manifest) do
      relative_paths = Html2rss::Registry::CatalogBuilder.config_paths(bundle_dir)
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
      manifest = build_fixture_manifest
      write_manifest!(bundle_dir, manifest)

      parsed = described_class.parse(File.read(File.join(bundle_dir, described_class::MANIFEST_FILE)))
      expect(parsed.canonical_bytes).to eq(manifest.canonical_bytes)
    end
  end
end
