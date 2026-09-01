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
    module Server
      # MCP server display name.
      SERVER_NAME = 'html2rss'
      # MCP server version (mirrors the gem version).
      SERVER_VERSION = Html2rss::VERSION
      # Loopback bind for HTTP transport (local use only).
      HTTP_BIND_HOST = '127.0.0.1'

      class << self
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
          Tools.register_all(server, registrar: method(:define_envelope_tool))
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
