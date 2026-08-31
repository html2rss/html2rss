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

        def instructions_text # rubocop:disable Metrics/MethodLength -- agent decision tree is the published contract
          <<~TEXT.strip
            html2rss MCP — decide which tool to call:

            1. Need articles now (no saved config)? → scrape_url (1 call)
               - strategy "auto" runs Faraday → Botasaurus AutoFallback. Do not retry with explicit faraday after auto.
               - Empty scrape is still success (articles-now). Follow next_step / guidance (read_runtime if Botasaurus unset).
            2. Need a reusable feed YAML? → capture_config → test_config → apply_config
               - capture_config returns YAML inside payload.yaml. Draft only: if destination is html2rss-configs, rewrite for directory.topics and explicit channel title/url. Strive enhance: true (false only when chrome leaks).
               - test_config runs schema + live extraction (min items). apply_config is the ship gate (isError on zero items). Confirm payload.item_count.
               - validate_config alone is for schema-only checks; on success next_step is test_config.
            3. Weak scrape/capture or recon (final URL, status, https→http, rel=alternate feeds)? → inspect_url only if weak or recon.
            4. Have a config already? → validate_config (must succeed) → test_config → apply_config
            5. Schema / extractors / strategies / runtime → resources html2rss://schema|extractors|strategies|runtime

            Prefer capture_config for durable config; scrape_url for one-shot extraction.
            Follow envelope next_step and guidance. Botasaurus needs BOTASAURUS_SCRAPER_URL in this process env (boolean at html2rss://runtime; the URL is never returned).
          TEXT
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
          register_scrape_url(server)
          register_inspect_url(server)
          register_capture_config(server)
          register_validate_config(server)
          register_test_config(server)
          register_apply_config(server)
        end

        def register_scrape_url(server)
          define_envelope_tool(
            server,
            name: 'scrape_url',
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

        def register_inspect_url(server)
          define_envelope_tool(
            server,
            name: 'inspect_url',
            description: 'Diagnostic page analysis (scrapers, SST, segments) plus recon: ' \
                         'final_url, status, scheme_downgrade, rel=alternate RSS/Atom feeds. ' \
                         'Use when scrape/capture is weak or you need those recon facts.',
            input_schema: Contract::INSPECT_INPUT_SCHEMA
          ) do |server_context:, url:, strategy: 'auto'| # rubocop:disable Lint/UnusedBlockArgument
            Outcome.inspect(payload: Inspect.call(url:, strategy:))
          end
        end

        def register_capture_config(server) # rubocop:disable Metrics/MethodLength
          define_envelope_tool(
            server,
            name: 'capture_config',
            description: 'Derive a reusable html2rss feed config from a URL. ' \
                         'Use when the goal is a durable YAML (then test_config → apply_config). ' \
                         'Returns YAML inside payload.yaml (same serializer as CLI capture). ' \
                         'Draft only — catalog feeds still need directory.topics and title/url; ' \
                         'strive enhance: true. Full schema options live in resource html2rss://schema.',
            input_schema: Contract::CAPTURE_INPUT_SCHEMA
          ) do |server_context:, url:, strategy: 'auto', items_selector: nil| # rubocop:disable Lint/UnusedBlockArgument
            capture_outcome(url:, strategy:, items_selector:)
          end
        end

        def capture_outcome(url:, strategy:, items_selector:) # rubocop:disable Metrics/MethodLength -- CaptureResult maps 1:1 onto Outcome
          plan = (strategy || :auto).to_sym
          result = Html2rss::Capture.build(url, strategy: plan, items_selector:)
          Outcome.capture(
            yaml: result.yaml,
            articles_count: result.articles_count,
            has_selectors: result.has_selectors,
            channel_title: result.channel_title,
            requested_strategy: plan,
            segment_strategy: result.segment_strategy,
            selected_strategy: result.selected_strategy,
            admission_drops: result.admission_drops
          )
        end

        def register_validate_config(server) # rubocop:disable Metrics/MethodLength -- description is the published contract
          define_envelope_tool(
            server,
            name: 'validate_config',
            description: 'Validate a feed config hash XOR yaml string against the html2rss JSON schema. ' \
                         'Call before test_config. Failures return isError with payload.errors. ' \
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

        def register_test_config(server)
          define_envelope_tool(
            server,
            name: 'test_config',
            description: 'Validate schema and execute live extraction (asserting >= min_items items). ' \
                         'Call after capture_config or validate_config; on success next_step is apply_config. ' \
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

        def register_apply_config(server)
          define_envelope_tool(
            server,
            name: 'apply_config',
            description: 'Apply a validated feed config (hash XOR yaml) and return RSS XML in payload.rss. ' \
                         'isError when the feed has zero items (ship gate). payload.item_count is RSS item count. ' \
                         'Use after test_config succeeds.',
            input_schema: Contract::APPLY_INPUT_SCHEMA
          ) do |server_context:, url:, config: nil, yaml: nil| # rubocop:disable Lint/UnusedBlockArgument
            apply_outcome(url:, config:, yaml:)
          end
        end

        def apply_outcome(url:, config:, yaml:)
          feed_config = ConfigArgument.parse(config:, yaml:).config
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

        def register_scrape_webpage_prompt(server) # rubocop:disable Metrics/MethodLength -- SDK prompt types stay together
          to_result = method(:prompt_result)
          text_for = method(:scrape_webpage_text)
          server.define_prompt(
            name: 'scrape-webpage',
            description: 'Guided one-shot scrape: one scrape_url call (auto already falls back)',
            arguments: [
              ::MCP::Prompt::Argument.new(name: 'url', description: 'URL to scrape', required: true)
            ]
          ) do |args, server_context:| # rubocop:disable Lint/UnusedBlockArgument
            to_result.call(text_for.call(args.fetch(:url)))
          end
        end

        def register_capture_feed_config_prompt(server) # rubocop:disable Metrics/MethodLength -- SDK prompt types stay together
          to_result = method(:prompt_result)
          text_for = method(:capture_feed_config_text)
          server.define_prompt(
            name: 'capture-feed-config',
            description: 'Guided capture → validate → apply; YAML draft plus catalog rewrite',
            arguments: [
              ::MCP::Prompt::Argument.new(name: 'url', description: 'URL to analyze', required: true)
            ]
          ) do |args, server_context:| # rubocop:disable Lint/UnusedBlockArgument
            to_result.call(text_for.call(args.fetch(:url)))
          end
        end

        def prompt_result(text)
          ::MCP::Prompt::Result.new(
            messages: [
              ::MCP::Prompt::Message.new(role: 'user', content: ::MCP::Content::Text.new(text))
            ]
          )
        end

        def scrape_webpage_text(url)
          <<~MSG.strip
            Scrape #{url} with scrape_url (strategy auto). One call is enough — auto already runs Faraday then Botasaurus.
            Follow envelope next_step and guidance. Call inspect_url only if articles are empty/weak or you need recon (final_url, status, scheme_downgrade, alternate_feeds).
            Do not retry scrape_url with explicit faraday after auto. Read html2rss://runtime if next_step is read_runtime.
            Return payload.items (not a raw JSON array).
          MSG
        end

        def capture_feed_config_text(url)
          <<~MSG.strip
            Build a reusable html2rss feed config for #{url}:
            1) capture_config — YAML is payload.yaml. Check payload.articles_count and payload.has_selectors. Strive to keep enhance: true (false only when chrome leaks into items).
            2) Follow next_step. If weak or you need recon, inspect_url. Auto already hops to Botasaurus; do not retry capture with botasaurus unless Faraday was blocked.
            3) test_config with yaml (or config hash) — schema + live extraction. On :schema failure, validate_config; on :execution/:min_items, recapture.
            4) apply_config — isError if zero items. Confirm payload.item_count before shipping.
            If the destination is html2rss-configs, rewrite the draft for directory.topics and explicit channel title/url. Return YAML.
          MSG
        end
      end
    end
  end
end
