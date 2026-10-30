# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

RSpec.describe Html2rss::MCP::Contract do
  let(:config_hash) { { channel: { url: 'https://example.com' } } }
  let(:config_yaml) { Html2rss::Config.to_yaml(config_hash) }

  describe 'STRATEGIES' do
    it 'is the published MCP set and excludes local_file', :aggregate_failures do
      expect(described_class::STRATEGIES).to eq(%w[auto default httpx botasaurus])
      expect(described_class::ALL_ACCEPTED_STRATEGIES).to eq(%w[auto default httpx botasaurus faraday browserless])
    end
  end

  describe '.assert_published_request!' do
    let(:base) { { channel: { url: 'https://example.com' } } }

    # rubocop:disable-next RSpec/ExampleLength -- published + migration strategy accept matrix
    it 'allows omitting strategy and published names', :aggregate_failures do
      expect { described_class.assert_published_request!(base) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: :default)) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: :httpx)) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: :faraday)) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: :browserless)) }.not_to raise_error
      expect { described_class.assert_published_request!(base.merge(strategy: 'botasaurus')) }.not_to raise_error
    end

    it 'rejects local_file strategy as symbol or string', :aggregate_failures do
      expect { described_class.assert_published_request!(base.merge(strategy: :local_file)) }
        .to raise_error(described_class::UnpublishedRequestError,
                        'MCP does not accept strategy local_file (published: auto, default, httpx, botasaurus)')
      expect { described_class.assert_published_request!(base.merge(strategy: 'local_file')) }
        .to raise_error(described_class::UnpublishedRequestError, /local_file/)
    end

    it 'accepts a request block that carries no local_file_path' do
      expect { described_class.assert_published_request!(base.merge(request: { timeout: 5 })) }.not_to raise_error
    end

    it 'rejects request.local_file_path even with a published strategy' do
      expect do
        described_class.assert_published_request!(
          base.merge(strategy: :default, request: { local_file_path: '/tmp/page.html' })
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
      expect(described_class::MCP_CONTRACT_VERSION).to eq(3)
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

    it 'pins the digest of the published tool catalog so client caches notice drift' do
      expect(described_class.catalog_fingerprint).to eq('61d6176d377fefef')
    end

    it 'changes when the published tool set changes' do # rubocop:disable RSpec/ExampleLength -- Tool construction is the mutation
      baseline = described_class.catalog_fingerprint
      extra_tool = Html2rss::MCP::Server::Tools::Tool.new(
        name: 'future_tool',
        title: 'Future',
        description: 'future',
        input_schema: { required: %w[url] },
        annotations: Html2rss::MCP::Contract::ANNOTATIONS_OPEN_WORLD,
        call: ->(**) {}
      )
      stub_const('Html2rss::MCP::Server::Tools::TOOLS', Html2rss::MCP::Server::Tools::TOOLS + [extra_tool])

      expect(described_class.catalog_fingerprint).not_to eq(baseline)
    end

    it 'changes when a tool oneOf branch changes' do # rubocop:disable RSpec/ExampleLength -- mutation setup encodes fingerprint sensitivity
      baseline = described_class.catalog_fingerprint
      mutated = Html2rss::MCP::Server::Tools::TOOLS.map do |entry|
        next entry unless entry.name == 'validate'

        schema = Html2rss::HashUtil.deep_dup(entry.input_schema)
        schema[:oneOf] = [{ required: %w[config yaml] }]
        entry.with(input_schema: schema)
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

    it 'pins the envelope JSON Schema document', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- schema literal
      expect(described_class.output_schema).to eq(
        type: 'object',
        additionalProperties: false,
        required: %w[ok next_step guidance payload],
        properties: {
          ok: { type: 'boolean' },
          next_step: { type: 'string', enum: Html2rss::MCP::Outcome::NextStep::ALL.keys.map(&:to_s) },
          guidance: { type: 'string' },
          payload: { type: 'object' }
        }
      )
    end
  end

  describe 'batch input schemas' do
    it 'pins batch_scrape input with limit and the scrape strategy property', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- schema literal
      schema = described_class.batch_urls_input_schema(
        urls_description: 'List of page URLs to scrape (1..25)',
        strategy_property: described_class::STRATEGY_PROPERTY,
        extra_properties: { limit: { type: 'integer', minimum: 1,
                                     description: 'Max articles per URL to keep (default 10)', default: 10 } }
      )

      expect(schema).to eq(
        type: 'object',
        properties: {
          urls: {
            type: 'array', items: described_class::URL_PROPERTY, minItems: 1, maxItems: 25,
            description: 'List of page URLs to scrape (1..25)'
          },
          strategy: described_class::STRATEGY_PROPERTY,
          concurrency: {
            type: 'integer', minimum: 1, maximum: 10,
            description: 'Max parallel worker threads (1..10, default: 5)', default: 5
          },
          limit: { type: 'integer', minimum: 1, description: 'Max articles per URL to keep (default 10)', default: 10 }
        },
        required: %w[urls]
      )
    end

    it 'pins batch_inspect input without limit and with the inspect strategy property', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- schema literal
      schema = described_class.batch_urls_input_schema(
        urls_description: 'List of page URLs to inspect (1..25)',
        strategy_property: described_class::INSPECT_STRATEGY_PROPERTY
      )

      expect(schema).to eq(
        type: 'object',
        properties: {
          urls: {
            type: 'array', items: described_class::URL_PROPERTY, minItems: 1, maxItems: 25,
            description: 'List of page URLs to inspect (1..25)'
          },
          strategy: described_class::INSPECT_STRATEGY_PROPERTY,
          concurrency: {
            type: 'integer', minimum: 1, maximum: 10,
            description: 'Max parallel worker threads (1..10, default: 5)', default: 5
          }
        },
        required: %w[urls]
      )
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

    it 'wraps the envelope as one text content block with the same JSON' do
      expect(described_class.response(outcome).content)
        .to eq([{ type: 'text', text: JSON.generate(outcome.to_h) }])
    end

    it 'sets isError from !ok' do
      response = described_class.response(
        Html2rss::MCP::Outcome.from_error(StandardError.new('boom'))
      )

      expect(response.error?).to be(true)
    end
  end
end
