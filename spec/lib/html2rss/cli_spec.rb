# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Html2rss::CLI do
  subject(:cli) { described_class.new }

  describe '#feed' do
    let(:rss_xml) { '<rss><channel><title>Example</title></channel></rss>' }

    before do
      allow(Html2rss).to receive(:feed).and_return(rss_xml)
    end

    it 'parses the YAML file and prints the RSS feed to stdout' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({ url: 'https://example.com' })

      expect { cli.feed('example.yml') }.to output("#{rss_xml}\n").to_stdout
    end

    it 'passes the feed_name to config_from_yaml_file' do
      allow(Html2rss).to receive(:config_from_yaml_file).with('example.yml',
                                                              'feed_name').and_return({ url: 'https://example.com' })

      expect { cli.feed('example.yml', 'feed_name') }.to output("#{rss_xml}\n").to_stdout
    end

    it 'passes the strategy option to the config' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.invoke(:feed, ['example.yml'], { strategy: 'browserless' })

      expect(Html2rss).to have_received(:feed).with(hash_including(strategy: :browserless))
    end

    it 'passes the params option to the config' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.invoke(:feed, ['example.yml'], { params: { 'foo' => 'bar' } })

      expect(Html2rss).to have_received(:feed).with(hash_including(params: { 'foo' => 'bar' }))
    end
  end

  describe '#auto' do
    let(:auto_rss_xml) { '<rss><channel><title>Auto Source</title></channel></rss>' }

    before do
      allow(Html2rss).to receive(:auto_source).and_return(auto_rss_xml)
    end

    it 'calls Html2rss.auto_source and prints the result to stdout' do
      expect { cli.auto('https://example.com') }.to output("#{auto_rss_xml}\n").to_stdout
    end

    it 'passes the strategy option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { strategy: 'browserless' })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :browserless, items_selector: nil)
    end

    it 'passes the items_selector option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { items_selector: '.item' })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :faraday, items_selector: '.item')
    end
  end

  describe '#schema' do
    let(:schema_hash) { { 'type' => 'object', 'title' => 'html2rss' } }

    before do
      allow(Html2rss::Config).to receive(:json_schema).and_return(schema_hash)
      allow(Html2rss::Config).to receive(:json_schema_json).and_call_original
    end

    it 'prints the schema JSON to stdout' do
      expect { cli.schema }.to output("#{JSON.pretty_generate(schema_hash)}\n").to_stdout
    end

    it 'supports compact output' do
      expect { cli.invoke(:schema, [], { pretty: false }) }
        .to output("#{JSON.generate(schema_hash)}\n").to_stdout
    end

    it 'writes the schema to the requested file path', :aggregate_failures do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'nested', 'schema.json')

        expect { cli.invoke(:schema, [], { write: path }) }.to output("#{path}\n").to_stdout
        expect(JSON.parse(File.read(path))).to eq(schema_hash)
      end
    end
  end

  describe '#validate' do
    let(:result) { instance_double(Dry::Validation::Result, success?: success, errors:) }
    let(:errors) { instance_double(Dry::Validation::MessageSet, to_h: { selectors: ['bad config'] }) }

    before do
      allow(Html2rss::Config).to receive(:validate_yaml).and_return(result)
    end

    context 'when the config is valid' do
      let(:success) { true }

      it 'prints a success message' do
        expect { cli.validate('config.yml') }.to output("Configuration is valid\n").to_stdout
      end
    end

    context 'when the config is invalid' do
      let(:success) { false }

      it 'raises a CLI error with runtime validation details' do
        expect { cli.validate('config.yml') }
          .to raise_error(Thor::Error, "Invalid configuration: #{errors.to_h}")
      end
    end
  end
end
