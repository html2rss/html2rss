# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

RSpec.describe Html2rss::MCP::Contract do
  let(:config_hash) { { channel: { url: 'https://example.com' } } }
  let(:config_yaml) { Html2rss::Config.to_yaml(config_hash) }

  describe 'STRATEGIES' do
    it 'is the published MCP set and excludes local_file' do
      expect(described_class::STRATEGIES).to eq(%w[auto faraday botasaurus])
    end
  end

  describe '.assert_published_request!' do
    let(:base) { { channel: { url: 'https://example.com' } } }

    it 'allows omitting strategy and published names', :aggregate_failures do
      expect { described_class.assert_published_request!(base) }.not_to raise_error
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

  describe 'BATCH_INSPECT_INPUT_SCHEMA' do
    let(:schema) { MCP::Tool::InputSchema.new(described_class::BATCH_INSPECT_INPUT_SCHEMA) }

    it 'validates valid arguments', :aggregate_failures do
      expect { schema.validate_arguments({ urls: ['https://example.com'] }) }.not_to raise_error
      expect { schema.validate_arguments({ urls: ['https://example.com'], strategy: 'faraday', concurrency: 3 }) }
        .not_to raise_error
    end

    it 'rejects empty urls array or missing urls', :aggregate_failures do
      expect { schema.validate_arguments({}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
      expect { schema.validate_arguments({ urls: [] }) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  describe 'BATCH_SCRAPE_INPUT_SCHEMA' do
    let(:schema) { MCP::Tool::InputSchema.new(described_class::BATCH_SCRAPE_INPUT_SCHEMA) }

    it 'validates valid arguments' do
      expect { schema.validate_arguments({ urls: ['https://example.com'], limit: 5 }) }.not_to raise_error
    end

    it 'rejects missing urls' do
      expect { schema.validate_arguments({ limit: 5 }) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  describe 'GENERATE_CATALOG_CONFIG_INPUT_SCHEMA' do
    let(:schema) { MCP::Tool::InputSchema.new(described_class::GENERATE_CATALOG_CONFIG_INPUT_SCHEMA) }

    it 'validates valid arguments', :aggregate_failures do
      expect { schema.validate_arguments({ url: 'https://example.com' }) }.not_to raise_error
      expect do
        schema.validate_arguments({ url: 'https://example.com', topics: %w[news tech], title: 'Example' })
      end.not_to raise_error
    end

    it 'rejects invalid topic enum' do
      expect do
        schema.validate_arguments({ url: 'https://example.com', topics: ['invalid_xyz'] })
      end.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end
  end

  describe 'CERTIFY_INPUT_SCHEMA' do
    let(:schema) { MCP::Tool::InputSchema.new(described_class::CERTIFY_INPUT_SCHEMA) }

    it 'validates valid arguments', :aggregate_failures do
      expect { schema.validate_arguments({ config: config_hash }) }.not_to raise_error
      expect { schema.validate_arguments({ yaml: config_yaml, check_live_feed: false }) }.not_to raise_error
    end

    it 'rejects missing or XOR violating arguments', :aggregate_failures do
      expect { schema.validate_arguments({}) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
      expect { schema.validate_arguments({ config: config_hash, yaml: config_yaml }) }
        .to raise_error(MCP::Tool::InputSchema::ValidationError)
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

    it 'closes the world only for validate_config' do
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
