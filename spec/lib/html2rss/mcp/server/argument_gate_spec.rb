# frozen_string_literal: true

require 'spec_helper'
require 'mcp'

RSpec.describe Html2rss::MCP::Server::ArgumentGate do
  subject(:server) { Html2rss::MCP::Server.build }

  let(:envelope) { ->(result) { JSON.parse(result.dig(:content, 0, :text), symbolize_names: true) } }

  it 'answers a missing required argument with the validate envelope', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- one envelope
    result = server.call_tool({ name: 'scrape', arguments: {} })

    expect(result[:isError]).to be(true)
    expect(envelope.call(result)).to include(
      ok: false, next_step: 'validate',
      payload: { class: 'Html2rss::MCP::Contract::InvalidArgumentsError',
                 message: 'Missing required arguments: url' }
    )
  end

  it 'lists every missing required argument', :aggregate_failures do
    sdk = MCP::Server.new(name: 'two').extend(described_class)
    sdk.define_tool(name: 'two', input_schema: { properties: { a: {}, b: {} }, required: %w[a b] }) { nil }

    expect(envelope.call(sdk.call_tool({ name: 'two', arguments: {} })).dig(:payload, :message))
      .to eq('Missing required arguments: a, b')
  end

  it 'keeps the input url on the error payload when one was given', :aggregate_failures do
    result = server.call_tool({ name: 'scrape', arguments: { url: 'https://example.com', limit: 'many' } })

    expect(envelope.call(result)[:payload]).to include(url: 'https://example.com')
    expect(envelope.call(result)[:payload][:message]).to start_with('Invalid arguments')
  end

  it 'treats a call without arguments as an empty argument hash' do
    result = server.call_tool({ name: 'scrape' })

    expect(envelope.call(result)).to include(next_step: 'validate', ok: false)
  end

  it 'leaves an unknown tool to the protocol server' do
    expect do
      server.call_tool({ name: 'nope', arguments: {} })
    end.to raise_error(MCP::Server::RequestHandlerError, /nope/)
  end

  it 'runs a tool whose arguments satisfy the schema', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- one envelope
    config = { channel: { url: 'https://example.com/news', title: 'News' },
               selectors: { items: { selector: 'article' }, title: { selector: 'h1' },
                            url: { selector: 'a', extractor: 'href' } } }
    request = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'validate', arguments: { config: } } }
    result = JSON.parse(server.handle_json(JSON.generate(request)), symbolize_names: true)[:result]

    expect(result[:isError]).to be(false)
    expect(envelope.call(result)).to include(ok: true, next_step: 'test')
  end

  # Pins what the gate relies on in the mcp gem: a gem upgrade that changes it must fail here, not in production.
  describe 'the mcp SDK contract the gate overrides' do
    let(:plain) do
      MCP::Server.new(name: 'plain').tap do |sdk|
        sdk.define_tool(name: 'needs_url',
                        input_schema: { properties: { url: { type: 'string' } },
                                        required: ['url'] }) do
          MCP::Tool::Response.new([{ type: 'text', text: 'ran' }])
        end
      end
    end

    it 'enters through call_tool(request) and exposes tools[name].input_schema', :aggregate_failures do
      schema = plain.tools['needs_url'].input_schema

      expect(MCP::Server.instance_method(:call_tool).parameters.first).to eq(%i[req request])
      expect(schema.missing_required_arguments({})).to eq(['url'])
      expect { schema.validate_arguments({ url: 1 }) }.to raise_error(MCP::Tool::InputSchema::ValidationError)
    end

    it 'answers a missing argument with plain text when the gate is absent', :aggregate_failures do
      request = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'needs_url', arguments: {} } }
      result = JSON.parse(plain.handle_json(JSON.generate(request)), symbolize_names: true)[:result]

      expect(result[:isError]).to be(true)
      expect(result.dig(:content, 0, :text)).to eq('Missing required arguments: url')
    end
  end
end
