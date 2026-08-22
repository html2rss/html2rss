# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::CatalogBuilder do
  let(:bundle_dir) { RegistryTestSupport::VALID_BUNDLE }

  before do
    manifest = build_fixture_manifest
    write_manifest!(bundle_dir, manifest)
  end

  describe '.entries' do
    subject(:entries) { described_class.entries(bundle_dir) }

    it 'returns sorted catalog entries', :aggregate_failures do
      expect(entries).not_to be_empty
      expect(entries.map(&:id)).to eq(entries.map(&:id).sort)
      expect(entries).to all(be_a(Html2rss::Registry::CatalogEntry))
    end

    context 'with anthropic.com/news' do
      subject(:entry) { entries.find { |candidate| candidate.id == 'anthropic.com/news' } }

      it 'maps anthropic identifiers' do
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
end
