# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Html2rss::Registry::CatalogBuilder do
  let(:bundle_dir) { RegistryTestSupport::VALID_BUNDLE }
  let(:manifest) { build_fixture_manifest }

  before do
    write_manifest!(bundle_dir, manifest)
  end

  describe '.entries' do
    subject(:entries) { described_class.entries(bundle_dir, manifest:) }

    it 'returns sorted catalog entries', :aggregate_failures do
      expect(entries).not_to be_empty
      expect(entries.map(&:id)).to eq(entries.map(&:id).sort)
      expect(entries).to all(be_a(Html2rss::Registry::CatalogEntry))
    end

    it 'ignores unlisted yaml files outside the manifest' do # rubocop:disable RSpec/ExampleLength
      extra_path = File.join(bundle_dir, 'configs/example.com/extra.yml')
      FileUtils.mkdir_p(File.dirname(extra_path))
      File.write(
        extra_path,
        "registry:\n  id: example.com/extra\ndirectory:\n  title: Extra\n  topics: [news]\n" \
        "channel:\n  url: https://example.com\nselectors:\n  items:\n    selector: li\n"
      )

      expect(entries.map(&:id)).not_to include('example.com/extra')
    ensure
      FileUtils.rm_f(extra_path)
    end

    context 'with anthropic.com/news' do
      subject(:entry) { entries.find { |candidate| candidate.id == 'anthropic.com/news' } }

      it 'maps anthropic identifiers from registry.id' do
        expect(entry).to have_attributes(
          id: 'anthropic.com/news',
          path: '/anthropic.com/news.rss'
        )
      end

      it 'maps anthropic titles and parameters', :aggregate_failures do
        expect(entry.directory[:title]).to eq('Anthropic — News')
        expect(entry.channel[:title]).to eq('Anthropic — News')
        expect(entry.parameters).to eq(schema: {}, defaults: {})
      end
    end
  end

  describe '.build_entry' do
    it 'maps parameterized configs to schema and defaults', :aggregate_failures do
      relative_path = 'configs/cnet.com/section_sub.yml'
      entry = described_class.build_entry(bundle_dir, relative_path)

      expect(entry.id).to eq('cnet.com/section_sub')
      expect(entry.parameters[:defaults]).to eq('section' => 'tech')
      expect(entry.parameters[:schema]['section']).to eq('type' => 'string')
    end
  end

  describe '.entry_id' do
    it 'requires registry.id' do
      expect do
        described_class.entry_id({ channel: { url: 'https://example.com' } }, 'configs/example.com/x.yml')
      end.to raise_error(described_class::MissingRegistryId, /Missing registry.id/)
    end
  end
end
