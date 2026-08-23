# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::CatalogBuilder do
  let(:anthropic_config) do
    {
      registry: { id: 'anthropic.com/news' },
      directory: { title: 'Anthropic — News', topics: ['ai'] },
      channel: { url: 'https://www.anthropic.com/news' },
      selectors: { items: { selector: 'li' } }
    }
  end

  let(:cnet_config) do
    {
      registry: { id: 'cnet.com/section_sub' },
      directory: { title: 'CNET Section', topics: ['tech'] },
      channel: { url: 'https://www.cnet.com/%{section}/' }, # rubocop:disable Style/FormatStringToken
      parameters: { section: { type: 'string', default: 'tech' } },
      selectors: { items: { selector: 'li' } }
    }
  end

  describe '.entries_from_configs' do
    subject(:entries) do
      described_class.entries_from_configs(
        'configs/anthropic.com/news.yml' => anthropic_config,
        'configs/cnet.com/section_sub.yml' => cnet_config
      )
    end

    it 'returns sorted catalog entries', :aggregate_failures do
      expect(entries.map(&:id)).to eq(%w[anthropic.com/news cnet.com/section_sub])
      expect(entries).to all(be_a(Html2rss::Registry::CatalogEntry))
    end

    it 'ignores configs not present in the path map' do
      expect(entries.map(&:id)).not_to include('example.com/extra')
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

  describe '.assemble_entry' do
    it 'maps parameterized configs to schema and defaults', :aggregate_failures do
      entry = described_class.assemble_entry('configs/cnet.com/section_sub.yml', cnet_config)

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
