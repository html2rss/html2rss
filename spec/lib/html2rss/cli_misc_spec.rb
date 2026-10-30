# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Html2rss::CLI do
  let(:run_command) { ->(name, args, options = {}) { described_class.new.invoke(name, args, options) } }

  describe '#inspect' do
    let(:wire) { { requested_url: 'https://a.test', surface_category: 'listing', articles_count: 2 } }
    let(:inspection) { instance_double(Html2rss::PageRecon::Diagnostics::Report, to_wire_h: wire) }

    before do
      allow(Html2rss).to receive_messages(inspect: inspection,
                                          batch_inspect: instance_double(
                                            Html2rss::Batch::BatchResult, results: [wire, wire]
                                          ))
    end

    it 'inspects a single url with the strategy and deep flag', :aggregate_failures do
      expect { run_command.call(:inspect, ['https://a.test'], { strategy: 'default', deep: true, format: 'json' }) }
        .to output("#{JSON.pretty_generate(wire)}\n").to_stdout
      expect(Html2rss).to have_received(:inspect).with('https://a.test', strategy: :default, deep: true)
    end

    it 'defaults to auto, no deep and text output', :aggregate_failures do
      expect { run_command.call(:inspect, ['https://a.test']) }
        .to output("https://a.test\n        Surface:  listing (2 articles)\n\n").to_stdout
      expect(Html2rss).to have_received(:inspect).with('https://a.test', strategy: :auto, deep: false)
    end

    it 'batch-inspects candidate files', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'list.txt')
        File.write(path, "https://a.test/1\n# c\nslug\thttps://a.test/2\n")

        expect { run_command.call(:inspect, [nil], { file: path, format: 'json' }) }
          .to output("#{JSON.pretty_generate([wire, wire])}\n").to_stdout
        expect(Html2rss).to have_received(:batch_inspect)
          .with(%w[https://a.test/1 https://a.test/2], strategy: :auto)
      end
    end

    it 'requires a target' do
      expect { run_command.call(:inspect, []) }
        .to raise_error(Thor::Error, 'A target URL, --file, or stdin (-) is required')
    end
  end

  describe '#schema' do
    it 'prints the pretty schema by default', :aggregate_failures do
      allow(Html2rss).to receive(:schema_json).and_return('{"a":1}')

      expect { run_command.call(:schema, []) }.to output("{\"a\":1}\n").to_stdout
      expect(Html2rss).to have_received(:schema_json).with(pretty: true)
    end

    it 'passes --no-pretty through', :aggregate_failures do
      allow(Html2rss).to receive(:schema_json).and_return('{}')

      expect { run_command.call(:schema, [], { pretty: false }) }.to output("{}\n").to_stdout
      expect(Html2rss).to have_received(:schema_json).with(pretty: false)
    end

    it 'writes to --write, creating directories, and prints the path', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss).to receive(:schema_json).and_return('{"a":1}')

      Dir.mktmpdir do |dir|
        target = File.join(dir, 'deep', 'schema.json')

        expect { run_command.call(:schema, [], { write: target }) }.to output("#{target}\n").to_stdout
        expect(File.read(target)).to eq("{\"a\":1}\n")
      end
    end
  end

  describe '#validate' do
    it 'forwards files, params and quiet to Validate.run', :aggregate_failures do
      allow(Html2rss::CLI::Validate).to receive(:run)

      run_command.call(:validate, %w[a.yml b.yml], { params: { 'x' => 'y' }, quiet: true })

      expect(Html2rss::CLI::Validate).to have_received(:run).with(%w[a.yml b.yml], params: { 'x' => 'y' }, quiet: true)
    end

    it 'defaults to empty params and not quiet' do
      allow(Html2rss::CLI::Validate).to receive(:run)

      run_command.call(:validate, [])

      expect(Html2rss::CLI::Validate).to have_received(:run).with([], params: {}, quiet: false)
    end
  end

  describe '#mcp' do
    it 'starts the stdio transport on the default port', :aggregate_failures do
      allow(Html2rss::MCP).to receive(:start)

      run_command.call(:mcp, [])

      expect(Html2rss::MCP).to have_received(:start).with(transport: :stdio, port: 8080)
    end

    it 'forwards transport and port' do
      allow(Html2rss::MCP).to receive(:start)

      run_command.call(:mcp, [], { transport: 'http', port: 9000 })

      expect(Html2rss::MCP).to have_received(:start).with(transport: :http, port: 9000)
    end
  end
end
