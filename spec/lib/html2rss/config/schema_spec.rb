# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../support/development/config_schema'

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

      expect(selectors_schema.fetch('properties').keys).to include('items', 'enclosure')

      pattern_schema = selectors_schema.fetch('patternProperties').values.first
      expect(pattern_schema.fetch('description')).to include('Dynamic selector definition')
    end
  end
end
