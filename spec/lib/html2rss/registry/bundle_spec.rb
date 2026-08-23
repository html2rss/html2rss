# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'yaml'

RSpec.describe Html2rss::Registry::Bundle do
  let(:bundle_dir) { RegistryTestSupport::VALID_BUNDLE }

  before do
    write_manifest!(bundle_dir, build_fixture_manifest)
  end

  describe '.load' do
    it 'loads verified configs and catalog entries', :aggregate_failures do
      bundle = described_class.load(bundle_dir, trust: :signed, public_keys:)

      expect(bundle.manifest.registry_id).to eq('test')
      expect(bundle.configs.keys).to include('anthropic.com/news', 'cnet.com/section_sub')
      expect(bundle.catalog_entries.map(&:id)).to eq(bundle.catalog_entries.map(&:id).sort)
    end

    it 'reads each config YAML file once' do # rubocop:disable RSpec/ExampleLength
      relative_paths = bundled_config_paths(bundle_dir)
      allow(YAML).to receive(:safe_load_file).and_call_original

      described_class.load(bundle_dir, trust: :signed, public_keys:)

      relative_paths.each do |relative_path|
        absolute_path = File.join(bundle_dir, relative_path)
        expect(YAML).to have_received(:safe_load_file).with(absolute_path, symbolize_names: true).once
      end
    end

    it 'rejects duplicate registry.id values' do # rubocop:disable RSpec/ExampleLength
      dir = File.join(RegistryTestSupport::FIXTURE_ROOT, 'duplicate-id')
      FileUtils.rm_rf(dir)
      FileUtils.cp_r(RegistryTestSupport::VALID_BUNDLE, dir)
      duplicate_config = File.join(dir, 'configs/duplicate.com/news.yml')
      FileUtils.mkdir_p(File.dirname(duplicate_config))
      FileUtils.cp(File.join(dir, 'configs/anthropic.com/news.yml'), duplicate_config)
      write_manifest!(dir, build_fixture_manifest(bundle_dir: dir))

      expect do
        described_class.load(dir, trust: :signed, public_keys:)
      end.to raise_error(Html2rss::Registry::InvalidConfig, %r{Duplicate registry.id values: anthropic.com/news})
    ensure
      FileUtils.rm_rf(dir)
    end

    it 'validates every bundled config' do
      with_invalid_bundle do |invalid_dir|
        expect { described_class.load(invalid_dir, trust: :integrity_only, public_keys:) }
          .to raise_error(Html2rss::Registry::InvalidConfig, /Invalid config/)
      end
    end
  end
end
