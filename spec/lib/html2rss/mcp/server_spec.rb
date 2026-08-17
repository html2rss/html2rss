# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'mcp'
require 'climate_control'

RSpec.describe Html2rss::MCP::Server do
  subject(:protocol_server) { described_class.build }

  let(:valid_config) do
    {
      channel: { url: 'https://example.com', title: 'Example', time_zone: 'UTC' },
      selectors: {
        items: { selector: 'div.item' },
        title: { selector: 'h2' },
        url: { selector: 'a', extractor: 'href' }
      }
    }
  end

  let(:call_tool) do
    lambda do |name, arguments|
      payload = {
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: { name:, arguments: }
      }
      JSON.parse(protocol_server.handle_json(JSON.generate(payload)), symbolize_names: true)
    end
  end

  let(:read_resource) do
    lambda do |uri|
      payload = {
        jsonrpc: '2.0',
        id: 2,
        method: 'resources/read',
        params: { uri: }
      }
      JSON.parse(protocol_server.handle_json(JSON.generate(payload)), symbolize_names: true)
    end
  end

  describe '.build' do
    # rubocop:disable RSpec/ExampleLength -- registration contract is one assertion story
    it 'registers tools, resources, prompts, and decision-tree instructions', :aggregate_failures do
      expect(protocol_server.tools.keys).to contain_exactly(
        'scrape_url', 'inspect_url', 'capture_config', 'validate_config', 'apply_config'
      )
      expect(protocol_server.prompts.keys).to contain_exactly('scrape-webpage', 'capture-feed-config')
      expect(protocol_server.instructions).to include('"auto" triggers faraday')
      expect(protocol_server.instructions).to include('capture_config')
      expect(protocol_server.tools['validate_config'].description).to include('html2rss://schema')
      expect(protocol_server.tools['capture_config'].description).to include('html2rss://schema')
      scrape_schema = protocol_server.tools['scrape_url'].input_schema.to_h
      inspect_schema = protocol_server.tools['inspect_url'].input_schema.to_h
      expect(scrape_schema.dig(:properties, :strategy, :description)).to include('fallback chain')
      expect(inspect_schema.dig(:properties, :strategy, :description)).to include('Faraday')
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'tools/call contracts' do
    describe 'scrape_url' do
      before do
        status = Html2rss::Status.build(articles: [], dedup_dropped: 0, admission_drops: { 'credit' => 1 })
        feed_result = instance_double(
          Html2rss::FeedResult,
          to_json_feed: { title: 'Channel', items: [{ title: 'A', url: 'https://example.com/a' }] },
          status:
        )
        allow(Html2rss).to receive(:auto_feed_result).and_return(feed_result)
      end

      # rubocop:disable RSpec/ExampleLength -- tools/call + meta contract
      it 'returns JSON items with Status meta via symbol-key kwargs', :aggregate_failures do
        result = call_tool.call('scrape_url', { url: 'https://example.com', strategy: 'auto' })

        expect(Html2rss).to have_received(:auto_feed_result).with(
          'https://example.com',
          hash_including(strategy: :auto)
        )
        expect(result.dig(:result, :isError)).to be(false)
        expect(JSON.parse(result.dig(:result, :content, 0, :text))).to eq(
          [{ 'title' => 'A', 'url' => 'https://example.com/a' }]
        )
        expect(result.dig(:result, :_meta)).to include(
          total: 1,
          requested_strategy: 'auto',
          channel_title: 'Channel',
          admission_drops: { credit: 1 }
        )
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'capture_config' do
      let(:capture_result) do
        Html2rss::Capture::CaptureResult.new(
          config: valid_config,
          articles_count: 3,
          channel_title: 'Example',
          has_selectors: true,
          segment_strategy: :list,
          admission_drops: {},
          selected_strategy: nil
        )
      end

      before do
        allow(Html2rss::Capture).to receive(:build).and_return(capture_result)
      end

      # rubocop:disable RSpec/ExampleLength -- tools/call + meta contract
      it 'returns config JSON and quality meta', :aggregate_failures do
        result = call_tool.call('capture_config', { url: 'https://example.com' })

        expect(Html2rss::Capture).to have_received(:build).with(
          'https://example.com',
          hash_including(strategy: :auto)
        )
        expect(result.dig(:result, :isError)).to be(false)
        expect(result.dig(:result, :_meta)).to include(
          articles_count: 3,
          channel_title: 'Example',
          has_selectors: true,
          requested_strategy: 'auto'
        )
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'validate_config' do
      it 'succeeds for a valid config', :aggregate_failures do
        result = call_tool.call('validate_config', { config: valid_config })

        expect(result.dig(:result, :isError)).to be(false)
        expect(result.dig(:result, :content, 0, :text)).to eq('Config is valid.')
      end

      it 'marks invalid configs as isError with json error details', :aggregate_failures do
        result = call_tool.call('validate_config', { config: { bad: true } })

        expect(result.dig(:result, :isError)).to be(true)
        error_payload = JSON.parse(result.dig(:result, :content, 0, :text))
        expect(error_payload).to be_a(Hash)
      end
    end

    describe 'apply_config' do
      before do
        allow(Html2rss).to receive(:feed).and_return('<rss/>')
      end

      # rubocop:disable RSpec/ExampleLength -- channel.url fill + RSS body
      it 'returns RSS XML from Html2rss.feed', :aggregate_failures do
        result = call_tool.call(
          'apply_config',
          { url: 'https://example.com', config: valid_config.except(:channel) }
        )

        expect(Html2rss).to have_received(:feed).with(
          hash_including(channel: hash_including(url: 'https://example.com'))
        )
        expect(result.dig(:result, :content, 0, :text)).to eq('<rss/>')
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'inspect_url' do
      before do
        allow(Html2rss::MCP::Server::Inspect).to receive(:call).and_return(
          { url: 'https://example.com', strategy: :faraday, html_response: true }
        )
      end

      # rubocop:disable RSpec/ExampleLength -- tools/call diagnostic contract
      it 'returns diagnostic JSON from Inspect', :aggregate_failures do
        result = call_tool.call('inspect_url', { url: 'https://example.com' })

        expect(Html2rss::MCP::Server::Inspect).to have_received(:call).with(
          url: 'https://example.com',
          strategy: 'auto'
        )
        expect(result.dig(:result, :isError)).to be(false)
        expect(JSON.parse(result.dig(:result, :content, 0, :text))).to include(
          'strategy' => 'faraday'
        )
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'error paths' do
      before do
        allow(Html2rss::Log).to receive(:error)
        allow(Html2rss::Log).to receive(:info)
      end

      it 'marks scrape_url failures as isError', :aggregate_failures do
        allow(Html2rss).to receive(:auto_feed_result).and_raise(StandardError, 'scrape boom')
        result = call_tool.call('scrape_url', { url: 'https://example.com' })

        expect(result.dig(:result, :isError)).to be(true)
        expect(result.dig(:result, :content, 0, :text)).to include('scrape boom')
      end

      it 'logs tool exceptions to the gem logger' do
        allow(Html2rss).to receive(:auto_feed_result).and_raise(StandardError, 'scrape boom')

        call_tool.call('scrape_url', { url: 'https://example.com' })

        expect(Html2rss::Log).to have_received(:error).with('mcp error StandardError: scrape boom')
      end

      it 'marks capture_config failures as isError' do
        allow(Html2rss::Capture).to receive(:build).and_raise(StandardError, 'capture boom')
        result = call_tool.call('capture_config', { url: 'https://example.com' })

        expect(result.dig(:result, :isError)).to be(true)
      end

      it 'marks apply_config failures as isError' do
        allow(Html2rss).to receive(:feed).and_raise(StandardError, 'feed boom')
        result = call_tool.call('apply_config', { url: 'https://example.com', config: valid_config })

        expect(result.dig(:result, :isError)).to be(true)
      end

      it 'marks inspect_url failures as isError' do
        allow(Html2rss::MCP::Server::Inspect).to receive(:call).and_raise(StandardError, 'inspect boom')
        result = call_tool.call('inspect_url', { url: 'https://example.com' })

        expect(result.dig(:result, :isError)).to be(true)
      end

      it 'marks validate_config exceptions as isError' do
        allow(Html2rss::Config).to receive(:validate).and_raise(StandardError, 'validate boom')
        result = call_tool.call('validate_config', { config: valid_config })

        expect(result.dig(:result, :isError)).to be(true)
      end
    end
  end

  describe 'resources/read' do
    it 'returns schema JSON' do
      result = read_resource.call('html2rss://schema')
      text = result.dig(:result, :contents, 0, :text)

      expect(JSON.parse(text)).to include('type' => 'object')
    end

    it 'lists extractor names without claiming full documentation' do
      result = read_resource.call('html2rss://extractors')
      names = JSON.parse(result.dig(:result, :contents, 0, :text))

      expect(names).to include('text', 'href')
    end

    it 'lists request strategies' do
      result = read_resource.call('html2rss://strategies')
      names = JSON.parse(result.dig(:result, :contents, 0, :text))

      expect(names).to include('faraday', 'botasaurus')
    end
  end

  describe 'prompts' do
    it 'embeds actionable tool guidance for scrape-webpage' do
      prompt = protocol_server.prompts['scrape-webpage']
      result = prompt.template({ url: 'https://example.com' }, server_context: nil)
      text = result.to_h.dig(:messages, 0, :content, :text)

      expect(text).to include('scrape_url').and include('botasaurus')
    end

    it 'embeds capture → validate → apply guidance' do
      prompt = protocol_server.prompts['capture-feed-config']
      result = prompt.template({ url: 'https://example.com' }, server_context: nil)
      text = result.to_h.dig(:messages, 0, :content, :text)

      expect(text).to include('capture_config').and include('validate_config')
    end
  end

  describe 'foreground request logging' do
    # rubocop:disable RSpec/ExampleLength -- start/done pair is one access-log story
    it 'logs tools/call start and done without leaking arguments', :aggregate_failures do
      allow(Html2rss::Log).to receive(:info)

      call_tool.call('validate_config', { config: valid_config })

      expect(Html2rss::Log).to have_received(:info).with('mcp start tools/call')
      expect(Html2rss::Log).to have_received(:info).with(
        a_string_matching(%r{\Amcp done tools/call tool=validate_config \d+\.\d+s\z})
      )
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '.start' do
    around do |example|
      previous_logger = Html2rss.logger
      previous_level = Html2rss.defaults.log_level
      example.run
    ensure
      Html2rss.configure do |config|
        config.logger = previous_logger
        config.log_level = previous_level
      end
    end

    before do
      allow(MCP::Server::Transports::StdioTransport).to receive(:new).and_return(
        instance_double(MCP::Server::Transports::StdioTransport, open: nil)
      )
      allow(Html2rss::Log).to receive(:info)
    end

    it 'opens stdio transport by default' do
      described_class.start(transport: :stdio)

      expect(MCP::Server::Transports::StdioTransport).to have_received(:new)
    end

    # rubocop:disable RSpec/ExampleLength -- stderr vs stdout split is the protocol contract
    it 'writes the start banner to stderr so stdio JSON-RPC stays on stdout', :aggregate_failures do
      allow(Html2rss::Log).to receive(:info).and_call_original
      banner = "html2rss MCP #{Html2rss::VERSION} starting transport=stdio"

      ClimateControl.modify(LOG_LEVEL: 'info') do
        expect { described_class.start(transport: :stdio) }
          .to output(a_string_including(banner)).to_stderr
          .and output('').to_stdout
      end
    end
    # rubocop:enable RSpec/ExampleLength

    it 'defaults the daemon log level to info when LOG_LEVEL is unset' do
      ClimateControl.modify(LOG_LEVEL: nil) do
        described_class.start(transport: :stdio)

        expect(Html2rss.defaults.log_level).to eq(Logger::INFO)
      end
    end

    it 'honors LOG_LEVEL for the daemon' do
      ClimateControl.modify(LOG_LEVEL: 'error') do
        described_class.start(transport: :stdio)

        expect(Html2rss.defaults.log_level).to eq(Logger::ERROR)
      end
    end

    # rubocop:disable RSpec/ExampleLength -- Host/Port bind contract
    it 'binds HTTP to loopback via Rackup WEBrick', :aggregate_failures do
      require 'rackup/handler/webrick'
      allow(Rackup::Handler::WEBrick).to receive(:run)

      described_class.start(transport: :http, port: 9090)

      expect(Rackup::Handler::WEBrick).to have_received(:run).with(
        an_instance_of(MCP::Server::Transports::StreamableHTTPTransport),
        hash_including(Host: '127.0.0.1', Port: 9090)
      )
    end
    # rubocop:enable RSpec/ExampleLength

    it 'rejects unknown transports' do
      expect { described_class.start(transport: :udp) }.to raise_error(ArgumentError, /Unknown transport/)
    end

    # rubocop:disable RSpec/ExampleLength -- LoadError messaging contract
    it 'raises an actionable LoadError when HTTP deps are missing' do
      allow(described_class).to receive(:require).and_wrap_original do |original, name|
        raise LoadError, 'cannot load such file -- rackup' if name == 'rackup'

        original.call(name)
      end

      expect { described_class.start(transport: :http) }
        .to raise_error(LoadError, /HTTP transport requires the rackup and webrick gems/)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'mcp 1.2 invocation shape' do
    # rubocop:disable RSpec/ExampleLength -- documents the SDK breakage we fixed
    it 'rejects the broken positional |args, context| tool signature' do
      broken = MCP::Tool.define(
        name: 'broken',
        description: 'broken',
        input_schema: { type: 'object', properties: { url: { type: 'string' } }, required: ['url'] }
      ) do |args, _server_context|
        args.fetch('url')
      end

      expect { broken.call(url: 'https://example.com') }.to raise_error(ArgumentError)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'accepts keyword args with server_context', :aggregate_failures do
      tool = protocol_server.tools['validate_config']

      response = tool.call(config: valid_config, server_context: nil)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be(false)
    end
  end

  describe Html2rss::MCP::Server::Inspect do
    let(:html) { File.read('spec/fixtures/local_feed_test.html') }
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: html,
        url: Html2rss::Url.from_absolute('https://example.com/blog'),
        headers: { 'content-type' => 'text/html' }
      )
    end

    before do
      allow(described_class).to receive(:fetch_response).and_return(response)
    end

    it 'reports strategy, scrapers, and SST segment stats', :aggregate_failures do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

      expect(result[:strategy]).to eq(:faraday)
      expect(result[:html_response]).to be(true)
      expect(result[:sst]).to include(:node_count, :segment_stats)
    end

    it 'builds a request session when fetching', :aggregate_failures do
      allow(described_class).to receive(:fetch_response).and_call_original
      session = instance_double(Html2rss::RequestSession, fetch_initial_response: response)
      allow(Html2rss::RequestSession).to receive(:build).and_return(session)

      expect(described_class.fetch_response('https://example.com/blog', :faraday)).to eq(response)
      expect(Html2rss::RequestSession).to have_received(:build)
    end

    it 'reports none_found when no scraper matches' do
      allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(
        Html2rss::AutoSource::Scraper::NoScraperFound.new(category: :unsupported_surface)
      )

      expect(described_class.scraper_info(Nokogiri::HTML::Document.parse(html)))
        .to eq(none_found: 'unsupported_surface')
    end

    it 'reports xhr_capture with query-stripped endpoints for botasaurus', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      captured_response = Html2rss::RequestService::Response.new(
        body: html,
        url: Html2rss::Url.from_absolute('https://example.com/blog'),
        headers: { 'content-type' => 'text/html' },
        captured_responses: [
          {
            'url' => 'https://api.example.com/v1/articles?token=secret',
            'body' => '[{"title":"Captured","url":"/a"}]'
          }
        ]
      )
      allow(described_class).to receive(:fetch_response).and_return(captured_response)

      result = described_class.call(url: 'https://example.com/blog', strategy: :botasaurus)

      expect(result[:xhr_capture]).to include(
        count: 1,
        candidate_articles: true,
        sample_endpoints: ['https://api.example.com/v1/articles']
      )
      expect(result[:xhr_capture][:sample_endpoints].first).not_to include('token=')
    end

    it 'omits xhr_capture when strategy is not botasaurus' do
      result = described_class.call(url: 'https://example.com/blog', strategy: :auto)

      expect(result).not_to have_key(:xhr_capture)
    end

    it 'returns error for non-HTML parsed bodies' do
      expect(described_class.scraper_info({})).to eq(error: 'Response is not HTML')
    end

    it 'returns nil SST stats when normalization fails' do
      allow(Html2rss::SST::Normalizer).to receive(:call).and_raise(ArgumentError)

      expect(described_class.sst_stats_from(response)).to be_nil
    end

    it 'returns empty segments when segmenter fails' do
      allow(Html2rss::AutoSource::Segmenter).to receive(:call).and_raise(StandardError)

      sst = Html2rss::SST::Normalizer.call(html)
      expect(described_class.discover_segments(sst, 'https://example.com/blog')).to eq([])
    end
  end
end
