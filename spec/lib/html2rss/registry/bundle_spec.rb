# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

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

    it 'validates every bundled config' do
      with_invalid_bundle do |invalid_dir|
        expect { described_class.load(invalid_dir, trust: :integrity_only, public_keys:) }
          .to raise_error(Html2rss::Registry::InvalidConfig, /Invalid config/)
      end
    end
  end
end
