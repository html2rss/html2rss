# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Thin MCP wire adapter over public html2rss APIs.
    #
    # Ownership: scraping/capture/validate/feed stay on gem entrypoints
    # ({Html2rss.auto_feed_result}, {Capture.build}, {Config.validate}, {Html2rss.feed_result}).
    # This module maps MCP kwargs to those APIs, then {Outcome} + {Contract} shape the envelope.
    #
    # Strategy note: MCP +auto+ passes through to FeedPipeline AutoFallback
    # (faraday → botasaurus). Concrete strategies are used as-is.
    # Botasaurus requires +BOTASAURUS_SCRAPER_URL+.
    module Server # rubocop:disable Metrics/ModuleLength
      # MCP server display name.
      SERVER_NAME = 'html2rss'
      # MCP server version (mirrors the gem version).
      SERVER_VERSION = Html2rss::VERSION
      # Loopback bind for HTTP transport (local use only).
      HTTP_BIND_HOST = '127.0.0.1'

      class << self # rubocop:disable Metrics/ClassLength
        ##
        # Starts the MCP server with the given transport.
        #
        # Points {Html2rss.logger} at +$stderr+ so stdio JSON-RPC on stdout stays
        # intact, and raises the process log level to +info+ unless +LOG_LEVEL+ is set.
        # A foreground watcher then sees the start banner, tool calls, and pipeline warns.
        #
        # @param transport [Symbol] +:stdio+ or +:http+
        # @param port [Integer] port for HTTP transport
        def start(transport: :stdio, port: 8080)
          raise ArgumentError, "Unknown transport: #{transport.inspect}" unless %i[stdio http].include?(transport)

          configure_daemon_logging!
          app = build
          Log.info(start_banner(transport:, port:))
          return start_http(app, port:) if transport == :http

          ::MCP::Server::Transports::StdioTransport.new(app).open
        end

        ##
        # Builds the configured MCP protocol server (tools/resources/prompts).
        #
        # @return [::MCP::Server]
        def build # rubocop:disable Metrics/MethodLength -- protocol server construction
          ::MCP::Server.new(
            name: SERVER_NAME,
            title: SERVER_NAME,
            version: SERVER_VERSION,
            instructions: instructions_text,
            configuration: protocol_configuration
          ).tap do |server|
            register_tools(server)
            register_resources(server)
            register_prompts(server)
          end
        end

        private

        def configure_daemon_logging!
          Html2rss.configure do |config|
            config.logger = Logger.new($stderr)
            config.log_level = ENV.fetch('LOG_LEVEL', :info)
          end
        end

        def start_banner(transport:, port:)
          bind = transport == :http ? " bind=#{HTTP_BIND_HOST}:#{port}" : ''
          "html2rss MCP #{SERVER_VERSION} starting transport=#{transport}#{bind}"
        end

        def protocol_configuration
          ::MCP::Configuration.new.tap do |config|
            config.exception_reporter = method(:report_protocol_exception)
            config.around_request = method(:around_protocol_request)
            config.validate_tool_call_results = true
          end
        end

        def report_protocol_exception(error, server_context)
          detail = server_context.is_a?(Hash) && server_context[:error]
          suffix = detail ? " (#{detail})" : ''
          Log.error("#{error.class}: #{error.message}#{suffix}")
        end

        def around_protocol_request(data)
          return yield unless log_protocol_request?(data)

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            Log.info(protocol_request_line('start', data))
            yield
          ensure
            duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            Log.info(protocol_request_line('done', data, duration:))
          end
        end

        def log_protocol_request?(data)
          method = data[:method]
          method.is_a?(String) &&
            method != ::MCP::Methods::PING &&
            !::MCP::Methods.notification?(method)
        end

        def protocol_request_line(phase, data, duration: nil)
          parts = ['mcp', phase, data[:method], *protocol_request_labels(data)]
          parts << format('%.2fs', duration) if duration
          parts << "error=#{data[:error]}" if data[:error]
          parts.join(' ')
        end

        def protocol_request_labels(data)
          [
            data[:tool_name] && "tool=#{data[:tool_name]}",
            data[:prompt_name] && "prompt=#{data[:prompt_name]}",
            data[:resource_uri] && "uri=#{data[:resource_uri]}"
          ].compact
        end

        def start_http(app, port:) # rubocop:disable Metrics/MethodLength -- require + bind + LoadError message
          require 'rackup'
          require 'rackup/handler/webrick'
          require 'webrick'

          handler = ::MCP::Server::Transports::StreamableHTTPTransport.new(app, stateless: true)
          Rackup::Handler::WEBrick.run(
            handler,
            Host: HTTP_BIND_HOST,
            Port: port,
            Logger: Html2rss.logger
          )
        rescue LoadError => error
          raise LoadError,
                'HTTP transport requires the rackup and webrick gems ' \
                "(#{error.message}). Install them or use --transport stdio."
        end

        def instructions_text
          Outcome::Playbook.instructions
        end

        def botasaurus_configured?
          !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
        end

        def tool_error_response(error)
          Log.error("mcp error #{error.class}: #{error.message}")
          Contract.response(Outcome.from_error(error))
        end

        def handle_tool_call
          Contract.response(yield)
        rescue StandardError => error
          tool_error_response(error)
        end

        # rubocop:disable Metrics/MethodLength -- listing fields stay together
        def define_envelope_tool(server, name:, description:, input_schema:,
                                 annotations: Contract::ANNOTATIONS_OPEN_WORLD)
          run = method(:handle_tool_call)
          server.define_tool(
            name:,
            title: Contract::TITLES.fetch(name.to_sym),
            description:,
            annotations:,
            input_schema:,
            output_schema: Contract.output_schema
          ) do |**kwargs|
            run.call { yield(**kwargs) }
          end
        end
        # rubocop:enable Metrics/MethodLength

        def register_tools(server)
          register_scrape(server)
          register_inspect(server)
          register_recon(server)
          register_batch_scrape(server)
          register_batch_inspect(server)
          register_batch_recon(server)
          register_capture(server)
          register_validate(server)
          register_test(server)
          register_apply(server)
        end

        def register_scrape(server)
          define_envelope_tool(
            server,
            name: 'scrape',
            description: 'One-shot article extraction as JSON Feed items. ' \
                         'Use when you need articles now without a saved config. ' \
                         'strategy "auto" triggers fallback chain (faraday → botasaurus) for JS-rendered sites.',
            input_schema: Contract::SCRAPE_INPUT_SCHEMA
          ) do |server_context:, url:, strategy: 'auto', limit: 25, items_selector: nil| # rubocop:disable Lint/UnusedBlockArgument
            scrape_outcome(url:, strategy:, limit:, items_selector:)
          end
        end

        def scrape_outcome(url:, strategy:, limit:, items_selector:)
          plan = (strategy || :auto).to_sym
          feed_result = Html2rss.auto_feed_result(url, strategy: plan, limit:, items_selector:)
          feed = feed_result.to_json_feed
          Outcome.scrape(
            items: feed[:items] || [],
            requested_strategy: plan,
            channel_title: feed[:title],
            admission_drops: feed_result.status.admission_drops,
            botasaurus_configured: botasaurus_configured?
          )
        end

        def register_inspect(server)
          define_envelope_tool(
            server,
            name: 'inspect',
            description: 'Diagnostic page analysis (scrapers, SST, segments) plus recon: ' \
                         'final_url, status, scheme_downgrade, rel=alternate RSS/Atom feeds. ' \
                         'Use when scrape/capture is weak or you need those recon facts.',
            input_schema: Contract::INSPECT_INPUT_SCHEMA
          ) do |server_context:, url:, strategy: 'auto'| # rubocop:disable Lint/UnusedBlockArgument
            Outcome.inspect(report: PageRecon::Diagnostics.call(url:, strategy:))
          end
        end

        def register_recon(server)
          define_envelope_tool(
            server,
            name: 'recon',
            description: 'Curation verdict and native_feed preference for a URL. ' \
                         'Use after inspect when alternates warrant deeper recon, or when you need BUILD/DEFER/DROP.',
            input_schema: Contract::RECON_INPUT_SCHEMA
          ) do |server_context:, url:, strategy: 'auto'| # rubocop:disable Lint/UnusedBlockArgument
            Outcome.recon(result: Html2rss.recon(url, strategy:))
          end
        end

        def register_batch_scrape(server)
          define_envelope_tool(
            server,
            name: 'batch_scrape',
            description: 'Scrape multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns structured JSON Feed items and extraction counts.',
            input_schema: Contract::BATCH_SCRAPE_INPUT_SCHEMA
          ) do |server_context:, urls:, strategy: 'auto', limit: 10, concurrency: Batch::DEFAULT_CONCURRENCY| # rubocop:disable Lint/UnusedBlockArgument
            batch_scrape_outcome(urls:, strategy:, limit:, concurrency:)
          end
        end

        def batch_scrape_outcome(urls:, strategy:, limit:, concurrency:)
          Outcome.batch_scrape(Batch.batch_scrape(urls:, strategy:, limit:, concurrency:))
        end

        def register_batch_inspect(server)
          define_envelope_tool(
            server,
            name: 'batch_inspect',
            description: 'Inspect multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns final redirected URLs, status codes, and rel="alternate" feeds.',
            input_schema: Contract::BATCH_INSPECT_INPUT_SCHEMA
          ) do |server_context:, urls:, strategy: 'auto', concurrency: Batch::DEFAULT_CONCURRENCY| # rubocop:disable Lint/UnusedBlockArgument
            batch_inspect_outcome(urls:, strategy:, concurrency:)
          end
        end

        def batch_inspect_outcome(urls:, strategy:, concurrency:)
          Outcome.batch_inspect(Batch.batch_inspect(urls:, strategy:, concurrency:))
        end

        def register_batch_recon(server)
          define_envelope_tool(
            server,
            name: 'batch_recon',
            description: 'Run recon across multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns verdict, native_feed, and surface classification per URL.',
            input_schema: Contract::BATCH_RECON_INPUT_SCHEMA
          ) do |server_context:, urls:, strategy: 'auto', concurrency: Batch::DEFAULT_CONCURRENCY| # rubocop:disable Lint/UnusedBlockArgument
            Outcome.batch_recon(Batch.batch_recon(urls:, strategy:, concurrency:))
          end
        end

        def register_capture(server) # rubocop:disable Metrics/MethodLength
          define_envelope_tool(
            server,
            name: 'capture',
            description: 'Derive a reusable html2rss feed config from a URL. ' \
                         'Use when the goal is a durable YAML (then test → apply). ' \
                         'Returns YAML inside payload.yaml (same serializer as CLI capture). ' \
                         'Draft only — catalog feeds still need directory.topics and title/url; ' \
                         'strive enhance: true. Full schema options live in resource html2rss://schema.',
            input_schema: Contract::CAPTURE_INPUT_SCHEMA
          ) do |server_context:, url:, strategy: 'auto', items_selector: nil, force: false, # rubocop:disable Lint/UnusedBlockArgument, Metrics/ParameterLists
                                    topics: nil, title: nil, summary: nil, enhance: nil,
                                    limit: nil, max_redirects: nil, max_requests: nil|
            capture_outcome(
              url:, strategy:, items_selector:, force:, topics:, title:, summary:,
              enhance:, limit:, max_redirects:, max_requests:
            )
          end
        end

        def capture_outcome(url:, strategy:, items_selector:, force: false, topics: nil, title: nil, # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists -- CaptureResult maps 1:1 onto Outcome
                            summary: nil, enhance: nil, limit: nil, max_redirects: nil, max_requests: nil)
          plan = (strategy || :auto).to_sym
          result = Html2rss::Capture.build(
            url,
            strategy: plan,
            items_selector:,
            force:,
            topics:,
            title:,
            summary:,
            enhance:,
            limit:,
            max_redirects:,
            max_requests:
          )
          Outcome.capture(
            yaml: result.yaml,
            articles_count: result.articles_count,
            has_selectors: result.has_selectors,
            channel_title: result.channel_title,
            requested_strategy: plan,
            segment_strategy: result.segment_strategy,
            selected_strategy: result.selected_strategy,
            admission_drops: result.admission_drops,
            native_feed: result.native_feed
          )
        end

        def register_validate(server) # rubocop:disable Metrics/MethodLength -- description is the published contract
          define_envelope_tool(
            server,
            name: 'validate',
            description: 'Validate a feed config hash XOR yaml string against the html2rss JSON schema. ' \
                         'Call before test. Failures return isError with payload.errors. ' \
                         'Full schema lives in resource html2rss://schema.',
            input_schema: Contract::CONFIG_XOR_SCHEMA,
            annotations: Contract::ANNOTATIONS_VALIDATE
          ) do |server_context:, config: nil, yaml: nil| # rubocop:disable Lint/UnusedBlockArgument
            validate_outcome(config:, yaml:)
          end
        end

        def validate_outcome(config:, yaml:)
          validation = Html2rss::Config.validate(ConfigArgument.parse(config:, yaml:).config)
          Outcome.validate(errors: validation.success? ? nil : validation.errors.to_h)
        end

        def register_test(server)
          define_envelope_tool(
            server,
            name: 'test',
            description: 'Validate schema and execute live extraction (asserting >= min_items items). ' \
                         'Call after capture or validate; on success next_step is apply. ' \
                         'Returns test summary in payload with sample items, timing, and failure_kind.',
            input_schema: Contract::TEST_INPUT_SCHEMA
          ) do |server_context:, config: nil, yaml: nil, min_items: 1, strategy: 'auto'| # rubocop:disable Lint/UnusedBlockArgument
            test_outcome(config:, yaml:, min_items:, strategy:)
          end
        end

        def test_outcome(config:, yaml:, min_items: 1, strategy: 'auto')
          feed_config = ConfigArgument.parse(config:, yaml:).config
          test_result = Html2rss.test(feed_config, min_items:, strategy: (strategy || :auto).to_sym)
          Outcome.test(test_result)
        end

        def register_apply(server)
          define_envelope_tool(
            server,
            name: 'apply',
            description: 'Apply a validated feed config (hash XOR yaml) and return RSS XML in payload.rss. ' \
                         'isError when the feed has zero items (ship gate). payload.item_count is RSS item count. ' \
                         'Use after test succeeds.',
            input_schema: Contract::APPLY_INPUT_SCHEMA
          ) do |server_context:, url:, config: nil, yaml: nil| # rubocop:disable Lint/UnusedBlockArgument
            apply_outcome(url:, config:, yaml:)
          end
        end

        def apply_outcome(url:, config:, yaml:)
          feed_config = HashUtil.deep_dup(ConfigArgument.parse(config:, yaml:).config)
          feed_config[:channel] ||= {}
          feed_config[:channel][:url] ||= url
          feed_result = Html2rss.feed_result(feed_config)
          rss = feed_result.to_rss
          Outcome.apply(rss: rss.to_s, item_count: rss.items.size, empty: feed_result.empty?)
        end

        def register_resources(server) # rubocop:disable Metrics/MethodLength
          configured = method(:botasaurus_configured?)
          server.define_resource(
            uri: 'html2rss://schema',
            name: 'Configuration JSON Schema',
            description: 'Full JSON Schema for html2rss feed configurations',
            mime_type: 'application/json'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            schema = Html2rss::Config.json_schema_json(pretty: true)
            [{ uri: 'html2rss://schema', mimeType: 'application/json', text: schema }]
          end

          server.define_resource(
            uri: 'html2rss://extractors',
            name: 'Available Extractors',
            description: 'Registered extractor names for selector configs ' \
                         '(full option docs live in html2rss://schema $defs)',
            mime_type: 'application/json'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            extractors = Html2rss::Selectors::Extractors::NAME_TO_CLASS.keys.map(&:to_s).sort
            [{ uri: 'html2rss://extractors', mimeType: 'application/json',
               text: JSON.pretty_generate(extractors) }]
          end

          server.define_resource(
            uri: 'html2rss://strategies',
            name: 'Available Strategies',
            description: 'Published MCP request strategy names',
            mime_type: 'application/json'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            [{ uri: 'html2rss://strategies', mimeType: 'application/json',
               text: JSON.generate(Contract::STRATEGIES) }]
          end

          server.define_resource(
            uri: 'html2rss://runtime',
            name: 'Runtime capabilities',
            description: 'Whether optional transports are configured in this MCP process (never leaks secrets)',
            mime_type: 'application/json'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            [{ uri: 'html2rss://runtime', mimeType: 'application/json',
               text: JSON.pretty_generate(botasaurus_configured: configured.call) }]
          end
        end

        def register_prompts(server)
          register_scrape_webpage_prompt(server)
          register_capture_feed_config_prompt(server)
        end

        # -- SDK prompt types stay together
        def register_scrape_webpage_prompt(server)
          to_result = method(:prompt_result)
          server.define_prompt(
            name: 'scrape-webpage',
            description: 'Guided one-shot scrape: one scrape call (auto already falls back)',
            arguments: [
              ::MCP::Prompt::Argument.new(name: 'url', description: 'URL to scrape', required: true)
            ]
          ) do |args, server_context:| # rubocop:disable Lint/UnusedBlockArgument
            to_result.call(Outcome::Playbook.scrape_webpage_prompt(args.fetch(:url)))
          end
        end

        # -- SDK prompt types stay together
        def register_capture_feed_config_prompt(server)
          to_result = method(:prompt_result)
          server.define_prompt(
            name: 'capture-feed-config',
            description: 'Guided capture → validate → apply; YAML draft plus catalog rewrite',
            arguments: [
              ::MCP::Prompt::Argument.new(name: 'url', description: 'URL to analyze', required: true)
            ]
          ) do |args, server_context:| # rubocop:disable Lint/UnusedBlockArgument
            to_result.call(Outcome::Playbook.capture_feed_config_prompt(args.fetch(:url)))
          end
        end

        def prompt_result(text)
          ::MCP::Prompt::Result.new(
            messages: [
              ::MCP::Prompt::Message.new(role: 'user', content: ::MCP::Content::Text.new(text))
            ]
          )
        end
      end
    end
  end
end
