# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'mcp'
require 'climate_control'
require 'rss'
require 'tmpdir'

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

  let(:get_prompt) do
    lambda do |name, arguments|
      payload = {
        jsonrpc: '2.0',
        id: 3,
        method: 'prompts/get',
        params: { name:, arguments: }
      }
      JSON.parse(protocol_server.handle_json(JSON.generate(payload)), symbolize_names: true)
    end
  end

  describe '.build' do
    # rubocop:disable RSpec/ExampleLength -- registration contract is one assertion story
    it 'registers tools, resources, prompts, and decision-tree instructions', :aggregate_failures do
      expect(protocol_server.title).to eq('html2rss')
      expect(protocol_server.configuration.validate_tool_call_results?).to be(true)
      expect(protocol_server.tools.keys).to contain_exactly(
        'scrape_url', 'inspect_url', 'capture_config', 'validate_config', 'apply_config',
        'batch_inspect_urls', 'batch_scrape_urls', 'generate_catalog_config', 'certify_config'
      )
      expect(protocol_server.prompts.keys).to contain_exactly('scrape-webpage', 'capture-feed-config')
      expect(protocol_server.instructions).to include('Faraday → Botasaurus AutoFallback')
      expect(protocol_server.instructions).to include('html2rss://runtime')
      expect(protocol_server.instructions).to include('generate_catalog_config')
      expect(protocol_server.instructions).to include('certify_config')
      expect(protocol_server.instructions).not_to include('_meta')
      expect(protocol_server.instructions).not_to include('try explicit "faraday"')
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

      # rubocop:disable RSpec/ExampleLength -- tools/call envelope contract
      it 'returns an envelope with items in payload and no _meta', :aggregate_failures do
        result = call_tool.call('scrape_url', { url: 'https://example.com', strategy: 'auto' })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(Html2rss).to have_received(:auto_feed_result).with(
          'https://example.com',
          hash_including(strategy: :auto)
        )
        expect(result.dig(:result, :isError)).to be(false)
        expect(result.dig(:result, :_meta)).to be_nil
        expect(result.dig(:result, :structuredContent)).to eq(envelope)
        expect(envelope).to include(ok: true, next_step: 'done')
        expect(envelope[:payload]).to include(
          total: 1,
          requested_strategy: 'auto',
          channel_title: 'Channel',
          items: [{ title: 'A', url: 'https://example.com/a' }],
          admission_drops: { credit: 1 }
        )
      end
      # rubocop:enable RSpec/ExampleLength

      it 'does not mark an empty scrape as isError (articles-now is not a ship gate)' do # rubocop:disable RSpec/ExampleLength
        feed_result = instance_double(
          Html2rss::FeedResult,
          to_json_feed: { title: 'Channel', items: [] },
          status: Html2rss::Status.build(articles: [], dedup_dropped: 0, admission_drops: {})
        )
        allow(Html2rss).to receive(:auto_feed_result).and_return(feed_result)

        result = call_tool.call('scrape_url', { url: 'https://example.com' })

        expect(result.dig(:result, :isError)).to be(false)
      end

      it 'points an empty scrape_url at read_runtime when Botasaurus is unset', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- tools/call next_step contract
        feed_result = instance_double(
          Html2rss::FeedResult,
          to_json_feed: { title: 'Channel', items: [] },
          status: Html2rss::Status.build(articles: [], dedup_dropped: 0, admission_drops: {})
        )
        allow(Html2rss).to receive(:auto_feed_result).and_return(feed_result)

        ClimateControl.modify(BOTASAURUS_SCRAPER_URL: nil) do
          result = call_tool.call('scrape_url', { url: 'https://example.com' })
          envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

          expect(result.dig(:result, :isError)).to be(false)
          expect(envelope[:next_step]).to eq('read_runtime')
        end
      end
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

      # rubocop:disable RSpec/ExampleLength -- tools/call envelope contract
      it 'returns YAML inside payload and quality fields without _meta', :aggregate_failures do
        yaml = Html2rss::Config.to_yaml(valid_config)
        allow(Html2rss::Config).to receive(:to_yaml).and_return(yaml)
        result = call_tool.call('capture_config', { url: 'https://example.com' })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(Html2rss::Capture).to have_received(:build).with(
          'https://example.com',
          hash_including(strategy: :auto)
        )
        expect(Html2rss::Config).to have_received(:to_yaml).with(valid_config)
        expect(result.dig(:result, :isError)).to be(false)
        expect(result.dig(:result, :_meta)).to be_nil
        expect(envelope).to include(ok: true, next_step: 'validate_config')
        expect(envelope[:payload]).to include(
          yaml:,
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
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(false)
        expect(envelope).to include(ok: true, next_step: 'apply_config', payload: {})
      end

      it 'accepts yaml XOR config so catalog files skip JSON re-encoding' do
        result = call_tool.call('validate_config', { yaml: Html2rss::Config.to_yaml(valid_config) })

        expect(result.dig(:result, :isError)).to be(false)
      end

      it 'marks XOR violations as isError' do
        result = call_tool.call('validate_config', { config: valid_config, yaml: 'channel: {}' })

        expect(result.dig(:result, :isError)).to be(true)
      end

      it 'rejects local_file in the parsed config', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- unpublished-strategy envelope
        result = call_tool.call(
          'validate_config',
          { config: valid_config.merge(strategy: :local_file, request: { local_file_path: '/etc/passwd' }) }
        )
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(true)
        expect(envelope).to include(ok: false, next_step: 'validate_config')
        expect(envelope.dig(:payload, :class)).to eq('Html2rss::MCP::Contract::UnpublishedRequestError')
      end

      it 'marks invalid configs as isError with json error details', :aggregate_failures do
        result = call_tool.call('validate_config', { config: { bad: true } })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(true)
        expect(envelope).to include(ok: false, next_step: 'validate_config')
        expect(envelope[:payload][:errors]).to be_a(Hash)
      end
    end

    describe 'apply_config' do
      let(:feed_result) do
        instance_double(
          Html2rss::FeedResult,
          empty?: false,
          to_rss: instance_double(RSS::Rss, to_s: '<rss/>', items: [Object.new])
        )
      end

      before do
        allow(Html2rss).to receive(:feed_result).and_return(feed_result)
      end

      # rubocop:disable RSpec/ExampleLength -- channel.url fill + RSS envelope
      it 'returns RSS XML from Html2rss.feed_result', :aggregate_failures do
        result = call_tool.call(
          'apply_config',
          { url: 'https://example.com', config: valid_config.except(:channel) }
        )
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(Html2rss).to have_received(:feed_result).with(
          hash_including(channel: hash_including(url: 'https://example.com'))
        )
        expect(result.dig(:result, :isError)).to be(false)
        expect(result.dig(:result, :_meta)).to be_nil
        expect(envelope).to include(ok: true, next_step: 'done')
        expect(envelope[:payload]).to include(rss: '<rss/>', item_count: 1)
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'apply_config unpublished local_file' do
      # rubocop:disable RSpec/ExampleLength -- security: isError without File.read
      it 'isError and does not read the local file', :aggregate_failures do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'secret.html')
          File.write(path, '<html><body><div class="item"><h2>Secret</h2><a href="/a">x</a></div></body></html>')
          read_paths = []
          allow(File).to receive(:read).and_wrap_original do |original, name, *rest, **kwargs|
            read_paths << name.to_s
            original.call(name, *rest, **kwargs)
          end

          result = call_tool.call(
            'apply_config',
            { url: 'https://example.com',
              config: valid_config.merge(strategy: :local_file, request: { local_file_path: path }) }
          )
          envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

          expect(result.dig(:result, :isError)).to be(true)
          expect(envelope).to include(ok: false, next_step: 'validate_config')
          expect(envelope.dig(:payload, :class)).to eq('Html2rss::MCP::Contract::UnpublishedRequestError')
          expect(read_paths).not_to include(path)
        end
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'apply_config ship gate' do
      let(:feed_result) do
        instance_double(
          Html2rss::FeedResult,
          empty?: true,
          to_rss: instance_double(RSS::Rss, to_s: '<rss/>', items: [])
        )
      end

      before do
        allow(Html2rss).to receive(:feed_result).and_return(feed_result)
      end

      it 'marks apply as isError and reports item_count from rss.items.size', :aggregate_failures do
        result = call_tool.call('apply_config', { url: 'https://example.com', config: valid_config })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(true)
        expect(result.dig(:result, :_meta)).to be_nil
        expect(envelope[:payload]).to include(item_count: 0)
      end
    end

    describe 'inspect_url' do
      before do
        allow(Html2rss::MCP::Inspect).to receive(:call).and_return(
          { requested_url: 'https://example.com', strategy: :faraday, html_response: true }
        )
      end

      # rubocop:disable RSpec/ExampleLength -- tools/call diagnostic envelope
      it 'returns diagnostic JSON from Inspect', :aggregate_failures do
        result = call_tool.call('inspect_url', { url: 'https://example.com' })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(Html2rss::MCP::Inspect).to have_received(:call).with(
          url: 'https://example.com',
          strategy: 'auto'
        )
        expect(result.dig(:result, :isError)).to be(false)
        expect(envelope[:payload]).to include(strategy: 'faraday')
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe 'batch_inspect_urls' do
      let(:batch_result) do
        Html2rss::MCP::Batch::BatchResult.new(
          total: 2, successful: 2,
          results: [{ url: 'https://example.com/1', ok: true }, { url: 'https://example.com/2', ok: true }]
        )
      end

      before do
        allow(Html2rss::MCP::Batch).to receive(:inspect_urls).and_return(batch_result)
      end

      it 'returns batch inspection payload and next_step done', :aggregate_failures do
        result = call_tool.call('batch_inspect_urls', { urls: ['https://example.com/1', 'https://example.com/2'] })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(false)
        expect(envelope).to include(ok: true, next_step: 'done')
        expect(envelope[:payload]).to include(total: 2, successful: 2)
      end
    end

    describe 'batch_scrape_urls' do
      let(:batch_result) do
        Html2rss::MCP::Batch::BatchResult.new(
          total: 1, successful: 1,
          results: [{ url: 'https://example.com', ok: true, items_count: 3 }]
        )
      end

      before do
        allow(Html2rss::MCP::Batch).to receive(:scrape_urls).and_return(batch_result)
      end

      it 'returns batch scrape payload and next_step done', :aggregate_failures do
        result = call_tool.call('batch_scrape_urls', { urls: ['https://example.com'] })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(false)
        expect(envelope).to include(ok: true, next_step: 'done')
        expect(envelope[:payload]).to include(total: 1, successful: 1)
      end
    end

    describe 'generate_catalog_config' do
      let(:catalog_result) do
        Html2rss::MCP::CatalogConfig::CatalogResult.new(
          yaml: "directory:\n  title: Example\n", domain: 'example.com', native_feed_detected: false,
          alternate_feeds: [], articles_count: 5, suggested_topics: ['news']
        )
      end

      before do
        allow(Html2rss::MCP::CatalogConfig).to receive(:generate).and_return(catalog_result)
      end

      it 'returns generated catalog config and next_step certify_config', :aggregate_failures do
        result = call_tool.call('generate_catalog_config', { url: 'https://example.com' })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(false)
        expect(envelope).to include(ok: true, next_step: 'certify_config')
        expect(envelope[:payload]).to include(domain: 'example.com', yaml: "directory:\n  title: Example\n")
      end
    end

    describe 'certify_config' do
      let(:report) do
        Html2rss::MCP::Certify::CertificationReport.new(
          valid: true, errors: nil, live_check: { item_count: 3, warnings: [] }
        )
      end

      before do
        allow(Html2rss::MCP::Certify).to receive(:check).and_return(report)
      end

      it 'returns certification report payload and next_step done', :aggregate_failures do
        result = call_tool.call('certify_config', { config: valid_config })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(false)
        expect(envelope).to include(ok: true, next_step: 'done')
        expect(envelope[:payload]).to include(valid: true)
      end
    end

    describe 'error paths' do
      before do
        allow(Html2rss::Log).to receive(:error)
        allow(Html2rss::Log).to receive(:info)
      end

      it 'marks scrape_url failures as isError', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- envelope error shape
        allow(Html2rss).to receive(:auto_feed_result).and_raise(StandardError, 'scrape boom')
        result = call_tool.call('scrape_url', { url: 'https://example.com' })
        envelope = JSON.parse(result.dig(:result, :content, 0, :text), symbolize_names: true)

        expect(result.dig(:result, :isError)).to be(true)
        expect(envelope).to include(ok: false, next_step: 'inspect_url')
        expect(envelope[:payload]).to include(class: 'StandardError', message: 'scrape boom')
      end

      it 'keeps Botasaurus configuration failure envelope and logs free of the env URL value', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- leak contract
        secret = 'http://127.0.0.1:4010/secret-token'
        allow(Html2rss).to receive(:auto_feed_result).and_raise(
          Html2rss::RequestService::BotasaurusConfigurationError,
          'BOTASAURUS_SCRAPER_URL is required for strategy=botasaurus.'
        )

        ClimateControl.modify(BOTASAURUS_SCRAPER_URL: secret) do
          result = call_tool.call('scrape_url', { url: 'https://example.com', strategy: 'botasaurus' })
          text = result.dig(:result, :content, 0, :text)
          envelope = JSON.parse(text, symbolize_names: true)

          expect(result.dig(:result, :isError)).to be(true)
          expect(envelope[:next_step]).to eq('read_runtime')
          expect(text).not_to include('127.0.0.1')
          expect(text).not_to include('secret-token')
          expect(Html2rss::Log).to have_received(:error).with(
            'mcp error Html2rss::RequestService::BotasaurusConfigurationError: ' \
            'BOTASAURUS_SCRAPER_URL is required for strategy=botasaurus.'
          )
        end
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
        allow(Html2rss).to receive(:feed_result).and_raise(StandardError, 'feed boom')
        result = call_tool.call('apply_config', { url: 'https://example.com', config: valid_config })

        expect(result.dig(:result, :isError)).to be(true)
      end

      it 'marks inspect_url failures as isError' do
        allow(Html2rss::MCP::Inspect).to receive(:call).and_raise(StandardError, 'inspect boom')
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

    it 'lists the published MCP strategies without local_file', :aggregate_failures do
      result = read_resource.call('html2rss://strategies')
      names = JSON.parse(result.dig(:result, :contents, 0, :text))

      expect(names).to eq(%w[auto faraday botasaurus])
      expect(names).not_to include('local_file')
    end

    it 'reports botasaurus_configured without leaking the URL', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010/secret-token') do
        result = read_resource.call('html2rss://runtime')
        text = result.dig(:result, :contents, 0, :text)

        expect(JSON.parse(text)).to eq('botasaurus_configured' => true)
        expect(text).not_to include('127.0.0.1')
        expect(text).not_to include('secret-token')
      end
    end
  end

  describe 'tools/list' do
    it 'publishes title, annotations, and outputSchema on every tool', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- listing contract
      payload = { jsonrpc: '2.0', id: 4, method: 'tools/list', params: {} }
      result = JSON.parse(protocol_server.handle_json(JSON.generate(payload)), symbolize_names: true)
      tools = result.dig(:result, :tools)
      scrape = tools.find { |tool| tool[:name] == 'scrape_url' }
      validate = tools.find { |tool| tool[:name] == 'validate_config' }

      expect(tools).to all(include(:title, :annotations, :outputSchema))
      expect(scrape[:annotations]).to include(readOnlyHint: true, destructiveHint: false, openWorldHint: true)
      expect(validate[:annotations]).to include(openWorldHint: false)
      expect(scrape[:outputSchema][:required]).to include('ok', 'next_step', 'guidance', 'payload')
    end
  end

  describe 'prompts' do
    it 'embeds AutoFallback scrape guidance without an extra faraday hop', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      prompt = protocol_server.prompts['scrape-webpage']
      result = prompt.template({ url: 'https://example.com' }, server_context: nil)
      text = result.to_h.dig(:messages, 0, :content, :text)

      expect(text).to include('One call is enough').and include('Do not retry scrape_url with explicit faraday')
      expect(text).to include('next_step').and include('payload.items')
      expect(text).not_to include('_meta')
    end

    it 'embeds catalog rewrite and enhance: true on capture-feed-config', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      prompt = protocol_server.prompts['capture-feed-config']
      result = prompt.template({ url: 'https://example.com' }, server_context: nil)
      text = result.to_h.dig(:messages, 0, :content, :text)

      expect(text).to include('Strive to keep enhance: true').and include('directory.topics')
      expect(text).to include('payload.yaml').and include('payload.item_count')
      expect(text).not_to include('_meta')
    end

    it 'serves prompts/get through SDK argument types', :aggregate_failures do
      result = get_prompt.call('scrape-webpage', { url: 'https://example.com' })
      text = result.dig(:result, :messages, 0, :content, :text)

      expect(result).not_to have_key(:error)
      expect(text).to include('https://example.com').and include('next_step')
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

    it 'accepts keyword args with server_context', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      tool = protocol_server.tools['validate_config']

      response = tool.call(config: valid_config, server_context: nil)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be(false)
      expect(response.structured_content).to include(ok: true, next_step: 'apply_config')
      expect(response.meta).to be_nil
    end
  end
end
