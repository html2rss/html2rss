# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe Html2rss::Registry::Bundle do
  describe '.load' do
    it 'loads verified configs and catalog entries', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        bundle = described_class.load(bundle_dir, trust: :signed, public_keys:)

        expect(bundle.manifest.registry_id).to eq('test')
        expect(bundle.configs.keys).to include('anthropic.com/news', 'cnet.com/section_sub')
        expect(bundle.catalog_entries.map(&:id)).to eq(bundle.catalog_entries.map(&:id).sort)
      end
    end

    it 'reads each config YAML file once' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        relative_paths = bundled_config_paths(bundle_dir)
        allow(YAML).to receive(:safe_load_file).and_call_original

        described_class.load(bundle_dir, trust: :signed, public_keys:)

        relative_paths.each do |relative_path|
          absolute_path = File.join(bundle_dir, relative_path)
          expect(YAML).to have_received(:safe_load_file).with(absolute_path, symbolize_names: true).once
        end
      end
    end

    it 'rejects duplicate registry.id values' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        duplicate_config = File.join(bundle_dir, 'configs/duplicate.com/news.yml')
        FileUtils.mkdir_p(File.dirname(duplicate_config))
        FileUtils.cp(File.join(bundle_dir, 'configs/anthropic.com/news.yml'), duplicate_config)
        write_manifest!(bundle_dir, build_fixture_manifest(bundle_dir:))

        expect do
          described_class.load(bundle_dir, trust: :signed, public_keys:)
        end.to raise_error(
          Html2rss::Registry::InvalidConfig,
          %r{Duplicate or conflicting registry.id: anthropic.com/news}
        )
      end
    end

    it 'indexes registry.aliases into configs without duplicating catalog entries', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        config_path = File.join(bundle_dir, 'configs/anthropic.com/news.yml')
        yaml = YAML.safe_load_file(config_path)
        yaml['registry']['aliases'] = ['anthropic.com/press', 'anthropic.com/legacy-news']
        File.write(config_path, YAML.dump(yaml))
        write_manifest!(bundle_dir, build_fixture_manifest(bundle_dir:))

        bundle = described_class.load(bundle_dir, trust: :signed, public_keys:)

        canonical_config = bundle.configs['anthropic.com/news']
        expect(bundle.configs['anthropic.com/press']).to be(canonical_config)
        expect(bundle.configs['anthropic.com/legacy-news']).to be(canonical_config)
        expect(bundle.catalog_entries.map(&:id)).not_to include('anthropic.com/press', 'anthropic.com/legacy-news')
      end
    end

    it 'rejects conflicting aliases' do # rubocop:disable RSpec/ExampleLength
      with_copied_valid_bundle do |bundle_dir|
        config_path = File.join(bundle_dir, 'configs/anthropic.com/news.yml')
        yaml = YAML.safe_load_file(config_path)
        yaml['registry']['aliases'] = ['cnet.com/section_sub']
        File.write(config_path, YAML.dump(yaml))
        write_manifest!(bundle_dir, build_fixture_manifest(bundle_dir:))

        expect do
          described_class.load(bundle_dir, trust: :signed, public_keys:)
        end.to raise_error(
          Html2rss::Registry::InvalidConfig,
          %r{Duplicate or conflicting (?:alias|registry\.id): cnet\.com/section_sub}
        )
      end
    end

    it 'validates every bundled config' do
      with_invalid_bundle do |invalid_dir|
        expect { described_class.load(invalid_dir, trust: :integrity_only, public_keys:) }
          .to raise_error(Html2rss::Registry::InvalidConfig, /Invalid config/)
      end
    end
  end
end
