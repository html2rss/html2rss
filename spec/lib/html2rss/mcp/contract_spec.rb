# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

RSpec.describe Html2rss::MCP::Contract do
  let(:config_hash) { { channel: { url: 'https://example.com' } } }
  let(:config_yaml) { Html2rss::Config.to_yaml(config_hash) }

  describe 'STRATEGIES' do
    it 'is the published MCP set and excludes local_file' do
      expect(described_class::STRATEGIES).to eq(%w[auto default botasaurus faraday])
    end
  end

  describe '.assert_published_request!' do
    let(:base) { { channel: { url: 'https://example.com' } } }

    it 'allows omitting strategy and published names', :aggregate_failures do
      expect { described_class.assert_published_request!(base) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: :default)) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: :faraday)) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: 'botasaurus')) }.not_to raise_error
    end

    it 'rejects local_file strategy as symbol or string', :aggregate_failures do
      expect { described_class.assert_published_request!(base.merge(strategy: :local_file)) }
        .to raise_error(described_class::UnpublishedRequestError, /local_file/)
      expect { described_class.assert_published_request!(base.merge(strategy: 'local_file')) }
        .to raise_error(described_class::UnpublishedRequestError, /local_file/)
    end

    it 'rejects request.local_file_path even with a published strategy' do
      expect do
        described_class.assert_published_request!(
          base.merge(strategy: :faraday, request: { local_file_path: '/tmp/page.html' })
        )
      end.to raise_error(described_class::UnpublishedRequestError, /local_file_path/)
    end
  end

  describe 'URL_PROPERTY' do
    it 'declares format uri so clients can reject non-URLs at the schema layer' do
      expect(described_class::URL_PROPERTY).to include(type: 'string', format: 'uri')
    end
  end

  describe 'XOR input schema vs ConfigArgument' do
    let(:schema) { MCP::Tool::InputSchema.new(described_class::CONFIG_XOR_SCHEMA) }

    # Shared table: published schema and runtime XOR must admit the same five cases.
    {
      'neither' => { kwargs: {}, parse: :raise, schema: :invalid },
      'both' => { kwargs: { config: :hash, yaml: :yaml }, parse: :raise, schema: :invalid },
      'config' => { kwargs: { config: :hash }, parse: :ok, schema: :valid },
      'yaml' => { kwargs: { yaml: :yaml }, parse: :ok, schema: :valid },
      'blank yaml' => { kwargs: { yaml: "  \n" }, parse: :raise, schema: :invalid }
    }.each do |label, row|
      it "treats #{label} the same at parse and InputSchema", :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- shared XOR table row
        kwargs = row[:kwargs].transform_values do |value|
          case value
          when :hash then config_hash
          when :yaml then config_yaml
          else value
          end
        end

        if row[:parse] == :ok
          expect { Html2rss::MCP::ConfigArgument.parse(**kwargs) }.not_to raise_error
        else
          expect { Html2rss::MCP::ConfigArgument.parse(**kwargs) }.to raise_error(ArgumentError)
        end

        if row[:schema] == :valid
          expect { schema.validate_arguments(kwargs) }.not_to raise_error
        else
          expect { schema.validate_arguments(kwargs) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
        end
      end
    end
  end

  describe 'MCP_CONTRACT_VERSION' do
    it 'is independent of the gem version constant', :aggregate_failures do
      expect(described_class::MCP_CONTRACT_VERSION).to be_a(Integer)
      expect(described_class::MCP_CONTRACT_VERSION).to eq(2)
    end
  end

  describe '.catalog_tools' do
    it 'lists canonical tool names in stable order' do
      expect(described_class.catalog_tools).to eq(
        %w[apply batch_inspect batch_recon batch_scrape capture inspect recon scrape test validate]
      )
    end
  end

  describe '.catalog_fingerprint' do
    it 'is a stable 16-char hex digest for the published registry', :aggregate_failures do
      fingerprint = described_class.catalog_fingerprint
      expect(fingerprint).to match(/\A[0-9a-f]{16}\z/)
      expect(described_class.catalog_fingerprint).to eq(fingerprint)
    end

    it 'changes when the published tool set changes' do
      baseline = described_class.catalog_fingerprint
      extra_tool = { name: 'future_tool', kind: :url, input_schema: { required: %w[url] } }
      stub_const('Html2rss::MCP::Server::Tools::TOOLS', Html2rss::MCP::Server::Tools::TOOLS + [extra_tool])

      expect(described_class.catalog_fingerprint).not_to eq(baseline)
    end

    it 'changes when a tool oneOf branch changes' do # rubocop:disable RSpec/ExampleLength -- mutation setup encodes fingerprint sensitivity
      baseline = described_class.catalog_fingerprint
      mutated = Html2rss::MCP::Server::Tools::TOOLS.map do |entry|
        next entry unless entry.fetch(:name) == 'validate'

        schema = Html2rss::HashUtil.deep_dup(entry.fetch(:input_schema))
        schema[:oneOf] = [{ required: %w[config yaml] }]
        entry.merge(input_schema: schema)
      end
      stub_const('Html2rss::MCP::Server::Tools::TOOLS', mutated)

      expect(described_class.catalog_fingerprint).not_to eq(baseline)
    end
  end

  describe '.output_schema' do
    it 'validates an Outcome wire hash' do
      wire = Html2rss::MCP::Outcome.apply(rss: '<rss/>', item_count: 1).to_h
      schema = MCP::Tool::OutputSchema.new(described_class.output_schema)

      expect { schema.validate_result(wire) }.not_to raise_error
    end
  end

  describe 'annotations' do
    it 'marks tools read-only, non-destructive, and idempotent' do
      expect(described_class::ANNOTATIONS_OPEN_WORLD).to include(
        read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true
      )
    end

    it 'closes the world only for validate' do
      expect(described_class::ANNOTATIONS_VALIDATE).to include(open_world_hint: false)
    end
  end

  describe '.response' do
    let(:outcome) { Html2rss::MCP::Outcome.apply(rss: '<rss/>', item_count: 1) }

    it 'returns one compact JSON envelope as text and structuredContent', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- compact JSON budget
      allow(JSON).to receive(:pretty_generate).and_call_original
      allow(JSON).to receive(:generate).and_call_original

      response = described_class.response(outcome)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be(false)
      expect(response.meta).to be_nil
      expect(response.to_h).not_to have_key(:_meta)
      expect(JSON).not_to have_received(:pretty_generate)
      expect(JSON).to have_received(:generate).once
      expect(response.structured_content).to eq(outcome.to_h)
      expect(JSON.parse(response.content.first[:text], symbolize_names: true)).to eq(outcome.to_h)
    end

    it 'sets isError from !ok' do
      response = described_class.response(
        Html2rss::MCP::Outcome.from_error(StandardError.new('boom'))
      )

      expect(response.error?).to be(true)
    end
  end
end
