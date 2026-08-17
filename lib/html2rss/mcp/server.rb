# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Thin MCP wire adapter over public html2rss APIs.
    #
    # Ownership: scraping/capture/validate/feed stay on gem entrypoints
    # ({Html2rss.auto_json_feed}, {Capture.build}, {Config.validate}, {Html2rss.feed}).
    # This module only maps MCP kwargs ↔ those APIs and shapes Tool::Response.
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
        def build
          ::MCP::Server.new(
            name: SERVER_NAME,
            version: SERVER_VERSION,
            instructions: instructions_text,
            configuration: protocol_configuration
          ).tap do |server|
            register_tools(server)
            register_resources(server)
            register_prompts(server)
          end
        end

        ##
        # @param text [String]
        # @param error [Boolean]
        # @param meta [Hash, nil]
        # @return [::MCP::Tool::Response]
        def text_response(text, error: false, meta: nil)
          ::MCP::Tool::Response.new([{ type: 'text', text: }], error:, meta:)
        end

        ##
        # @param error [Exception]
        # @return [::MCP::Tool::Response]
        def error_response(error)
          Log.error("mcp error #{error.class}: #{error.message}")
          text_response("Error: #{error.message}", error: true)
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
               - Empty scrape is still success (articles-now). Check html2rss://runtime botasaurus_configured before pinning botasaurus.
            2. Need a reusable feed YAML? → capture_config → validate_config → apply_config
               - capture_config returns YAML (same as CLI). Draft only: if destination is html2rss-configs, rewrite for directory.topics and explicit channel title/url. Strive enhance: true (false only when chrome leaks).
               - validate_config / apply_config accept config hash XOR yaml string.
               - apply_config isError when zero RSS items (ship gate). Check _meta.item_count.
            3. Weak scrape/capture or recon (final URL, status, https→http, rel=alternate feeds)? → inspect_url only if weak or recon.
            4. Have a config already? → validate_config (must succeed) → apply_config
            5. Schema / extractors / strategies / runtime → resources html2rss://schema|extractors|strategies|runtime

            Prefer capture_config for durable config; scrape_url for one-shot extraction.
            Botasaurus needs BOTASAURUS_SCRAPER_URL in this process env (boolean at html2rss://runtime; the URL is never returned).
          TEXT
        end

        def register_tools(server)
          register_scrape_url(server)
          register_inspect_url(server)
          register_capture_config(server)
          register_validate_config(server)
          register_apply_config(server)
        end

        def register_scrape_url(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'scrape_url',
            description: 'One-shot article extraction as JSON Feed items. ' \
                         'Use when you need articles now without a saved config. ' \
                         'strategy "auto" triggers fallback chain (faraday → botasaurus) for JS-rendered sites.',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                strategy: {
                  type: 'string',
                  enum: %w[auto faraday botasaurus],
                  default: 'auto',
                  description: 'Request strategy (auto runs faraday → botasaurus fallback chain)'
                },
                limit: {
                  type: 'integer',
                  description: 'Max articles to keep (default 25)',
                  default: 25
                },
                items_selector: {
                  type: 'string',
                  description: 'Optional CSS selector hint for items'
                }
              },
              required: ['url']
            }
          ) do |server_context:, url:, strategy: 'auto', limit: 25, items_selector: nil| # rubocop:disable Lint/UnusedBlockArgument
            plan = (strategy || :auto).to_sym
            feed_result = Html2rss.auto_feed_result(url, strategy: plan, limit:, items_selector:)
            feed = feed_result.to_json_feed
            items = feed[:items] || []
            Server.text_response(JSON.generate(items), meta: {
                                   total: items.size,
                                   requested_strategy: plan.to_s,
                                   channel_title: feed[:title],
                                   **feed_result.status.to_h
                                 })
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_inspect_url(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'inspect_url',
            description: 'Diagnostic page analysis (scrapers, SST, segments) plus recon: ' \
                         'final_url, status, scheme_downgrade, rel=alternate RSS/Atom feeds. ' \
                         'Use when scrape/capture is weak or you need those recon facts.',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                strategy: {
                  type: 'string',
                  enum: %w[auto faraday botasaurus],
                  default: 'auto',
                  description: 'Request strategy (auto uses Faraday for cheap diagnostics; pin botasaurus when needed)'
                }
              },
              required: ['url']
            }
          ) do |server_context:, url:, strategy: 'auto'| # rubocop:disable Lint/UnusedBlockArgument
            Server.text_response(JSON.pretty_generate(Inspect.call(url:, strategy:)))
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_capture_config(server) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          server.define_tool(
            name: 'capture_config',
            description: 'Derive a reusable html2rss feed config from a URL. ' \
                         'Use when the goal is a durable YAML (then validate_config). ' \
                         'Returns YAML (same serializer as CLI capture) plus quality meta. ' \
                         'Draft only — catalog feeds still need directory.topics and title/url; ' \
                         'strive enhance: true. Full schema options live in resource html2rss://schema.',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                strategy: {
                  type: 'string',
                  enum: %w[auto faraday botasaurus],
                  default: 'auto',
                  description: 'Request strategy (auto runs faraday → botasaurus fallback chain)'
                },
                items_selector: {
                  type: 'string',
                  description: 'Optional CSS selector hint for items'
                }
              },
              required: ['url']
            }
          ) do |server_context:, url:, strategy: 'auto', items_selector: nil| # rubocop:disable Lint/UnusedBlockArgument
            plan = (strategy || :auto).to_sym
            result = Html2rss::Capture.build(url, strategy: plan, items_selector:)
            meta = {
              articles_count: result.articles_count,
              channel_title: result.channel_title,
              has_selectors: result.has_selectors,
              requested_strategy: plan.to_s
            }
            meta[:segment_strategy] = result.segment_strategy.to_s if result.segment_strategy
            meta[:selected_strategy] = result.selected_strategy.to_s if result.selected_strategy
            meta[:admission_drops] = result.admission_drops if result.admission_drops.any?
            Server.text_response(Config.to_yaml(result.config), meta:)
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_validate_config(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'validate_config',
            description: 'Validate a feed config hash XOR yaml string against the html2rss JSON schema. ' \
                         'Call before apply_config. Failures return isError with structured error details. ' \
                         'Full schema lives in resource html2rss://schema.',
            input_schema: {
              type: 'object',
              properties: {
                config: {
                  type: 'object',
                  description: 'Feed configuration hash with channel and selectors (XOR yaml)'
                },
                yaml: {
                  type: 'string',
                  description: 'Feed configuration YAML string (XOR config)'
                }
              }
            }
          ) do |server_context:, config: nil, yaml: nil| # rubocop:disable Lint/UnusedBlockArgument
            config_hash = ConfigArgument.parse(config:, yaml:).config
            validation = Html2rss::Config.validate(config_hash)

            if validation.success?
              Server.text_response('Config is valid.')
            else
              Server.text_response(JSON.generate(validation.errors.to_h), error: true)
            end
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_apply_config(server) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          server.define_tool(
            name: 'apply_config',
            description: 'Apply a validated feed config (hash XOR yaml) and return RSS XML. ' \
                         'isError when the feed has zero items (ship gate). _meta.item_count is RSS item count. ' \
                         'Use after validate_config succeeds.',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL (fills channel.url if missing)' },
                config: {
                  type: 'object',
                  description: 'Feed configuration hash with selectors (XOR yaml)'
                },
                yaml: {
                  type: 'string',
                  description: 'Feed configuration YAML string (XOR config)'
                }
              },
              required: ['url']
            }
          ) do |server_context:, url:, config: nil, yaml: nil| # rubocop:disable Lint/UnusedBlockArgument
            feed_config = ConfigArgument.parse(config:, yaml:).config
            feed_config[:channel] ||= {}
            feed_config[:channel][:url] ||= url

            feed_result = Html2rss.feed_result(feed_config)
            rss = feed_result.to_rss
            Server.text_response(rss.to_s, error: feed_result.empty?, meta: { item_count: rss.items.size })
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_resources(server) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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
                         '(full option docs live in html2rss://schema $defs)'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            extractors = Html2rss::Selectors::Extractors::NAME_TO_CLASS.keys.map(&:to_s).sort
            [{ uri: 'html2rss://extractors', mimeType: 'application/json',
               text: JSON.pretty_generate(extractors) }]
          end

          server.define_resource(
            uri: 'html2rss://strategies',
            name: 'Available Strategies',
            description: 'Registered request strategy names'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            strategies = Html2rss::RequestService.instance.strategy_names
            [{ uri: 'html2rss://strategies', mimeType: 'application/json',
               text: JSON.pretty_generate(strategies) }]
          end

          server.define_resource(
            uri: 'html2rss://runtime',
            name: 'Runtime capabilities',
            description: 'Whether optional transports are configured in this MCP process (never leaks secrets)',
            mime_type: 'application/json'
          ) do |server_context: nil| # rubocop:disable Lint/UnusedBlockArgument
            [{ uri: 'html2rss://runtime', mimeType: 'application/json',
               text: JSON.pretty_generate(
                 botasaurus_configured: !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
               ) }]
          end
        end

        def register_prompts(server) # rubocop:disable Metrics/MethodLength
          server.define_prompt(
            name: 'scrape-webpage',
            description: 'Guided one-shot scrape: one scrape_url call (auto already falls back)',
            arguments: [
              { name: 'url', description: 'URL to scrape', required: true }
            ]
          ) do |args, server_context:| # rubocop:disable Lint/UnusedBlockArgument
            url = args.fetch(:url)
            {
              messages: [
                {
                  role: 'user',
                  content: {
                    type: 'text',
                    text: <<~MSG.strip
                      Scrape #{url} with scrape_url (strategy auto). One call is enough — auto already runs Faraday then Botasaurus.
                      Call inspect_url only if articles are empty/weak or you need recon (final_url, status, scheme_downgrade, alternate_feeds).
                      Do not retry scrape_url with explicit faraday after auto. Check html2rss://runtime if botasaurus_configured is false.
                      Return the structured articles JSON.
                    MSG
                  }
                }
              ]
            }
          end

          server.define_prompt(
            name: 'capture-feed-config',
            description: 'Guided capture → validate → apply; YAML draft plus catalog rewrite',
            arguments: [
              { name: 'url', description: 'URL to analyze', required: true }
            ]
          ) do |args, server_context:| # rubocop:disable Lint/UnusedBlockArgument
            url = args.fetch(:url)
            {
              messages: [
                {
                  role: 'user',
                  content: {
                    type: 'text',
                    text: <<~MSG.strip
                      Build a reusable html2rss feed config for #{url}:
                      1) capture_config — YAML draft. Check _meta.articles_count and has_selectors. Strive to keep enhance: true (false only when chrome leaks into items).
                      2) If weak or you need recon, inspect_url. Auto already hops to Botasaurus; do not retry capture with botasaurus unless Faraday was blocked.
                      3) validate_config with yaml (or config hash) — must not be isError
                      4) apply_config — isError if zero items. Confirm _meta.item_count before shipping.
                      If the destination is html2rss-configs, rewrite the draft for directory.topics and explicit channel title/url. Return YAML.
                    MSG
                  }
                }
              ]
            }
          end
        end
      end
    end
  end
end
