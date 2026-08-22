# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Html2rss::Config::Schema do
  describe '.json_schema' do
    subject(:json_schema) { described_class.json_schema }

    it 'includes channel as a required top-level property' do
      expect(json_schema.fetch('required')).to include('channel')
    end

    it 'does not require strategy at the top level' do
      expect(json_schema.fetch('required')).not_to include('strategy')
    end

    it 'exposes strategy as an optional non-null string', :aggregate_failures do
      strategy_schema = json_schema.dig('properties', 'strategy')

      expect(strategy_schema.fetch('type')).to eq('string')
      expect(strategy_schema).not_to include('enum')
      expect(strategy_schema.dig('not', 'type')).to eq('null')
    end

    it 'leaves runtime-registered strategy names to runtime validation' do
      expect(json_schema.dig('properties', 'strategy')).to match(
        'type' => 'string',
        'not' => { 'type' => 'null' }
      )
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

    it 'documents pagination configuration under items selector', :aggregate_failures do
      pagination_schema = json_schema.dig('properties', 'selectors', 'properties', 'items', 'properties', 'pagination')

      expect(pagination_schema).to include('oneOf')
      strategies = pagination_schema.fetch('oneOf')[1].dig('properties', 'strategy', 'enum')
      expect(strategies).to contain_exactly('rel_next', 'custom_selector', 'url_template', 'offset', 'json_cursor')
    end

    it 'publishes extractor and post-processor catalogs under $defs', :aggregate_failures do
      extractors = json_schema.dig('$defs', 'extractors')
      post_processors = json_schema.dig('$defs', 'post_processors')

      expect(extractors.keys).to match_array(Html2rss::Selectors::Extractors::NAME_TO_CLASS.keys.map(&:to_s))
      expect(post_processors.keys).to match_array(Html2rss::Selectors::PostProcessors::NAME_TO_CLASS.keys.map(&:to_s))
    end

    it 'wires selector extractor and post_process via oneOf $refs', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      pattern = json_schema.dig('properties', 'selectors', 'patternProperties').values.first
      extractor_refs = pattern.dig('properties', 'extractor', 'oneOf').map { |entry| entry.fetch('$ref') }
      post_process_one_of = pattern.dig('properties', 'post_process', 'items', 'oneOf')
      post_process_refs = post_process_one_of.map { |entry| entry.fetch('$ref') }

      expect(extractor_refs).to match_array(
        Html2rss::Selectors::Extractors::NAME_TO_CLASS.keys.map { |name| "#/$defs/extractors/#{name}" }
      )
      expect(post_process_refs).to match_array(
        Html2rss::Selectors::PostProcessors::NAME_TO_CLASS.keys.map { |name| "#/$defs/post_processors/#{name}" }
      )
      expect(pattern.dig('properties', 'extractor')).not_to include('enum')
      expect(pattern.dig('properties', 'post_process', 'items')).not_to include('properties')
    end

    it 'documents gsub options for AI-consumable authoring', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      gsub = json_schema.dig('$defs', 'post_processors', 'gsub')

      expect(gsub.fetch('description')).not_to be_empty
      expect(gsub.fetch('examples')).not_to be_empty
      expect(gsub.dig('properties', 'name', 'const')).to eq('gsub')
      expect(gsub.fetch('required')).to include('name', 'pattern', 'replacement')
      expect(gsub.dig('properties', 'pattern', 'type')).to eq('string')
      expect(gsub.dig('properties', 'replacement', 'type')).to eq('string')
    end

    it 'documents template string option', :aggregate_failures do
      template = json_schema.dig('$defs', 'post_processors', 'template')

      expect(template.fetch('description')).not_to be_empty
      expect(template.fetch('examples')).not_to be_empty
      expect(template.fetch('required')).to include('name', 'string')
      expect(template.dig('properties', 'string', 'type')).to eq('string')
    end

    it 'aligns pagination schema keys with runtime pager config keys', :aggregate_failures do
      # Schema keys must match runtime pager keys (start_page/step/start_offset), not a generic `start`.
      pagination_properties = json_schema.dig(
        'properties', 'selectors', 'properties', 'items', 'properties', 'pagination', 'oneOf', 1, 'properties'
      )

      expect(pagination_properties.keys).to include('start_page', 'step', 'start_offset', 'increment')
      expect(pagination_properties.keys).not_to include('start')
    end

    it 'includes the runtime auto_source scraper options', :aggregate_failures do
      scraper_schema = json_schema.dig('properties', 'auto_source', 'properties', 'scraper', 'properties')

      expect(scraper_schema).to include('microdata', 'schema', 'json_state', 'xhr_articles', 'semantic_html', 'html')
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
      expect(selectors_schema.dig('categories',
                                  'description')).to include('runtime validation enforces those references')
    end

    it 'does not expose internal validation helper properties' do
      expect(json_schema.fetch('properties')).not_to include('dynamic_params_error')
    end

    it 'exposes botasaurus request options and constraints', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      botasaurus_schema = json_schema.dig('properties', 'request', 'properties', 'botasaurus')
      botasaurus = botasaurus_schema.fetch('properties')
      window_size = botasaurus.fetch('window_size')

      expect(botasaurus.fetch('execution_mode').fetch('enum'))
        .to contain_exactly('auto', 'request', 'browser')
      expect(botasaurus.fetch('navigation_mode').fetch('enum'))
        .to contain_exactly('auto', 'get', 'google_get', 'google_get_bypass', 'organic_get')
      expect(botasaurus.dig('max_retries', 'minimum')).to eq(0)
      expect(botasaurus.dig('max_retries', 'maximum')).to eq(3)
      expect(botasaurus.dig('wait_timeout_seconds', 'minimum')).to eq(1)
      expect(botasaurus.dig('wait_timeout_seconds', 'maximum')).to eq(30)
      expect(botasaurus).to have_key('scroll')
      expect(botasaurus).not_to have_key('scroll_to_bottom')
      expect(botasaurus).to have_key('block_trackers')
      expect(botasaurus).to have_key('cookies')
      expect(botasaurus).to have_key('headers')
      expect(window_size.fetch('type')).to eq('object')
      expect(window_size.fetch('additionalProperties')).to be false
      expect(window_size.dig('properties', 'width')).to include('exclusiveMinimum' => 0)
      expect(window_size.dig('properties', 'height')).to include('exclusiveMinimum' => 0)
      expect(botasaurus_schema.fetch('additionalProperties')).to be false
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
