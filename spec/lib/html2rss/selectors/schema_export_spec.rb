# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::SchemaExport do
  describe '.for_post_processor' do
    it 'exports the full object fragment for a post-processor with optional options', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fragment = described_class.for_post_processor(name: :substring, klass: Html2rss::Selectors::PostProcessors::Substring)

      expect(fragment[:type]).to eq('object')
      expect(fragment[:title]).to eq('substring')
      expect(fragment[:description]).to eq(Html2rss::Selectors::PostProcessors::Substring::DESCRIPTION)
      expect(fragment[:examples]).to eq(Html2rss::Selectors::PostProcessors::Substring::EXAMPLES)
      expect(fragment[:properties]).to eq(
        name: { type: 'string', const: 'substring' },
        start: { type: 'integer' },
        end: { type: 'integer' }
      )
      expect(fragment[:required]).to eq(%w[name start])
      expect(fragment[:additionalProperties]).to be(true)
    end

    it 'stringifies symbol names for the title and the name property', :aggregate_failures do
      fragment = described_class.for_post_processor(name: :gsub, klass: Html2rss::Selectors::PostProcessors::Gsub)

      expect(fragment[:title]).to eq('gsub')
      expect(fragment[:properties][:name]).to eq(type: 'string', const: 'gsub')
    end

    it 'keeps the name when given as a string' do
      fragment = described_class.for_post_processor(name: 'gsub', klass: Html2rss::Selectors::PostProcessors::Gsub)

      expect(fragment[:title]).to eq('gsub')
    end

    it 'requires only name for post-processors without required options', :aggregate_failures do
      fragment = described_class.for_post_processor(name: :parse_uri, klass: Html2rss::Selectors::PostProcessors::ParseUri)

      expect(fragment[:required]).to eq(%w[name])
      expect(fragment[:properties]).to eq(name: { type: 'string', const: 'parse_uri' })
    end
  end

  describe '.for_extractor' do
    it 'exports a string const fragment with description and examples', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fragment = described_class.for_extractor(name: :text, klass: Html2rss::Selectors::Extractors::Text)

      expect(fragment).to eq(
        type: 'string',
        const: 'text',
        title: 'text',
        description: Html2rss::Selectors::Extractors::Text::DESCRIPTION,
        examples: Html2rss::Selectors::Extractors::Text::EXAMPLES
      )
    end

    it 'stringifies a symbol name' do
      fragment = described_class.for_extractor(name: :attribute, klass: Html2rss::Selectors::Extractors::Attribute)

      expect(fragment[:const]).to eq('attribute')
    end
  end

  describe '.json_type_for' do
    it 'maps a single Ruby type and a list of Ruby types to JSON Schema types', :aggregate_failures do
      expect(described_class.json_type_for(Integer)).to eq('integer')
      expect(described_class.json_type_for([String, Hash])).to eq(%w[string object])
    end
  end

  describe '.property_schema_for' do
    it 'wraps the JSON type in a type hash' do
      expect(described_class.property_schema_for([String, Hash])).to eq(type: %w[string object])
    end
  end

  describe '.post_processor_required' do
    it 'lists name followed by required option names only' do
      expect(described_class.post_processor_required(Html2rss::Selectors::PostProcessors::Substring))
        .to eq(%w[name start])
    end
  end

  describe '.post_processor_properties' do
    it 'maps each option to its JSON type after the const name' do
      expect(described_class.post_processor_properties('gsub', Html2rss::Selectors::PostProcessors::Gsub)).to eq(
        name: { type: 'string', const: 'gsub' },
        pattern: { type: 'string' },
        replacement: { type: %w[string object] }
      )
    end
  end

  describe 'registry exports' do
    it 'exports every post-processor class under its registry name', :aggregate_failures do
      Html2rss::Selectors::PostProcessors::NAME_TO_CLASS.each do |name, klass|
        expect(klass.schema_export[:title]).to eq(name.to_s)
      end
    end

    it 'exports every extractor class under its registry name', :aggregate_failures do
      Html2rss::Selectors::Extractors::NAME_TO_CLASS.each do |name, klass|
        expect(klass.schema_export[:title]).to eq(name.to_s)
      end
    end

    it 'caps the gsub pattern length in its JSON Schema fragment' do
      gsub = Html2rss::Selectors::PostProcessors::Gsub.schema_export

      expect(gsub.dig(:properties, :pattern, :maxLength)).to eq(Html2rss::Selectors::PostProcessors::Gsub::MAX_PATTERN_LENGTH)
    end
  end
end
