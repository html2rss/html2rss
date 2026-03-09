# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Html2rss::Config::Schema do
  describe '.json_schema' do
    subject(:json_schema) { described_class.json_schema }

    it 'includes required top-level properties' do
      expect(json_schema.fetch('required')).to include('strategy', 'channel')
    end

    it 'enforces presence of selectors or auto_source' do
      expect(json_schema.fetch('anyOf'))
        .to contain_exactly({ 'required' => ['selectors'] }, { 'required' => ['auto_source'] })
    end

    it 'embeds the AutoSource defaults' do
      expected_default = JSON.parse(JSON.generate(Html2rss::AutoSource::DEFAULT_CONFIG))

      expect(json_schema.dig('properties', 'auto_source', 'default')).to eq(expected_default)
    end

    it 'documents dynamic selector configuration', :aggregate_failures do
      selectors_schema = json_schema.dig('properties', 'selectors')

      expect(selectors_schema.fetch('properties').keys).to include('items', 'enclosure', 'guid', 'categories')

      pattern_schema = selectors_schema.fetch('patternProperties').values.first
      expect(pattern_schema.fetch('description')).to include('Dynamic selector definition')
    end

    it 'includes the runtime auto_source scraper options', :aggregate_failures do
      scraper_schema = json_schema.dig('properties', 'auto_source', 'properties', 'scraper', 'properties')

      expect(scraper_schema).to include('microdata', 'schema', 'json_state', 'semantic_html', 'html')
      expect(json_schema.dig('properties', 'auto_source', 'default', 'scraper', 'microdata', 'enabled')).to be(true)
    end

    it 'enforces non-empty selector reference arrays', :aggregate_failures do
      selectors_schema = json_schema.dig('properties', 'selectors', 'properties')

      expect(selectors_schema.dig('guid', 'minItems')).to eq(1)
      expect(selectors_schema.dig('categories', 'minItems')).to eq(1)
    end

    it 'documents runtime enforcement of selector references', :aggregate_failures do
      selectors_schema = json_schema.dig('properties', 'selectors', 'properties')

      expect(selectors_schema.dig('guid', 'description')).to include('runtime validation enforces those references')
      expect(selectors_schema.dig('categories', 'description')).to include('runtime validation enforces those references')
    end
  end

  describe '.path' do
    it 'points to an existing packaged schema artifact', :aggregate_failures do
      expect(described_class.path).to end_with('schema/html2rss-config.schema.json')
      expect(File.exist?(described_class.path)).to be(true)
    end
  end

  describe Html2rss::Config do
    describe '.json_schema_json' do
      it 'serializes the generated schema' do
        expect(JSON.parse(described_class.json_schema_json)).to eq(described_class.json_schema)
      end
    end

    describe '.schema_path' do
      it 'matches the schema module path' do
        expect(described_class.schema_path).to eq(Html2rss::Config::Schema.path)
      end
    end

    describe 'packaged schema artifact' do
      it 'matches the generated schema exactly' do
        packaged_schema = JSON.parse(File.read(described_class.schema_path))

        expect(packaged_schema).to eq(described_class.json_schema)
      end
    end
  end
end
