# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Configures and starts the MCP protocol server.
    module Server # rubocop:disable Metrics/ModuleLength
      # MCP server display name.
      SERVER_NAME = 'html2rss'
      # MCP server version (mirrors the gem version).
      SERVER_VERSION = Html2rss::VERSION

      class << self # rubocop:disable Metrics/ClassLength
        ##
        # Starts the MCP server with the given transport.
        #
        # @param transport [Symbol] +:stdio+ or +:http+
        # @param port [Integer] port for HTTP transport
        def start(transport: :stdio, port: 8080) # rubocop:disable Metrics/MethodLength
          app = build_server

          case transport
          when :stdio
            transport_instance = ::MCP::Server::Transports::StdioTransport.new(app)
            transport_instance.open
          when :http
            require 'rack'
            handler = ::MCP::Server::Transports::StreamableHTTPTransport.new(app, stateless: true)
            Rack::Handler::WEBrick.run(handler, Port: port, Logger: Html2rss.logger)
          else
            raise ArgumentError, "Unknown transport: #{transport.inspect}"
          end
        end

        private

        def build_server
          ::MCP::Server.new(
            name: SERVER_NAME,
            version: SERVER_VERSION,
            instructions: instructions_text
          ).tap do |server|
            register_tools(server)
            register_resources(server)
            register_prompts(server)
          end
        end

        def instructions_text
          'Automated web scraping via html2rss. ' \
            'Use scrape_url to extract articles, capture_config to build reusable ' \
            'feed configs, or inspect_url for deep page analysis. ' \
            'Botasaurus strategy handles JavaScript-rendered pages (requires BOTASAURUS_SCRAPER_URL).'
        end

        def register_tools(server)
          register_scrape_url(server)
          register_inspect_url(server)
          register_capture_config(server)
          register_validate_config(server)
          register_apply_config(server)
        end

        def register_scrape_url(server) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
          server.define_tool( # rubocop:disable Metrics/BlockLength
            name: 'scrape_url',
            description: 'Scrape a URL and return structured articles as hashes',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                strategy: {
                  type: 'string',
                  enum: %w[auto faraday botasaurus],
                  default: 'auto',
                  description: 'Request strategy'
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
          ) do |args, _server_context|
            url = args.fetch('url')
            strategy = (args['strategy'] || 'auto').to_sym
            limit = args['limit'] || 25
            items_selector = args['items_selector']

            response = fetch_response(url, strategy)
            auto_source_opts = Config.auto_source_config(
              url:,
              items_selector:,
              request_controls: Config::RequestControls.from_shortcut(strategy:),
              limit:
            )[:auto_source] || AutoSource::DEFAULT_CONFIG

            result = AutoSource.new(response, auto_source_opts).articles.map do |article|
              {
                id: article.id,
                title: article.title,
                description: article.description,
                url: article.url.to_s,
                image: article.image&.to_s,
                author: article.author,
                published_at: article.published_at&.iso8601,
                categories: article.categories,
                guid: article.guid
              }.compact
            end

            meta = { total: result.size }
            { content: [{ type: 'text', text: JSON.generate(result) }], _meta: meta }
          rescue StandardError => error
            { content: [{ type: 'text', text: "Error: #{error.message}" }], isError: true }
          end
        end

        def register_inspect_url(server) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          server.define_tool(
            name: 'inspect_url',
            description: 'Deep page analysis: scrapers, SST stats, segments, and scores',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                strategy: {
                  type: 'string',
                  enum: %w[auto faraday botasaurus],
                  default: 'auto',
                  description: 'Request strategy'
                }
              },
              required: ['url']
            }
          ) do |args, _server_context|
            url = args.fetch('url')
            strategy = (args['strategy'] || 'auto').to_sym

            response = fetch_response(url, strategy)
            parsed = response.parsed_body

            result = {
              url:,
              content_type: response.content_type,
              html_response: response.html_response?,
              scraper_eligibility: scraper_info(parsed),
              sst_stats: sst_stats_from(response)
            }

            if response.html_response?
              sst = sst_document(response)
              if sst
                result[:sst] = {
                  node_count: sst.node_count,
                  degraded: sst.degraded,
                  segment_stats: segment_stats(sst, url)
                }
              end
            end

            { content: [{ type: 'text', text: JSON.pretty_generate(result) }] }
          rescue StandardError => error
            { content: [{ type: 'text', text: "Error: #{error.message}" }], isError: true }
          end
        end

        def register_capture_config(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'capture_config',
            description: 'Analyze a URL and produce a reusable html2rss feed config hash',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                strategy: {
                  type: 'string',
                  enum: %w[auto faraday botasaurus],
                  default: 'auto',
                  description: 'Request strategy'
                },
                items_selector: {
                  type: 'string',
                  description: 'Optional CSS selector hint for items'
                }
              },
              required: ['url']
            }
          ) do |args, _server_context|
            url = args.fetch('url')
            strategy = (args['strategy'] || 'auto').to_sym
            items_selector = args['items_selector']

            result = Html2rss::Capture.build(url, strategy:, items_selector:)

            { content: [{ type: 'text', text: JSON.pretty_generate(result.config) }] }
          rescue StandardError => error
            { content: [{ type: 'text', text: "Error: #{error.message}" }], isError: true }
          end
        end

        def register_validate_config(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'validate_config',
            description: 'Validate a feed config hash against the html2rss JSON schema',
            input_schema: {
              type: 'object',
              properties: {
                config: {
                  type: 'object',
                  description: 'Feed configuration hash with channel and selectors'
                }
              },
              required: ['config']
            }
          ) do |args, _server_context|
            config = args.fetch('config')
            config_hash = HashUtil.deep_symbolize_keys(config, context: 'config')
            validation = Html2rss::Config.validate(config_hash)

            if validation.success?
              { content: [{ type: 'text', text: 'Config is valid.' }] }
            else
              { content: [{ type: 'text', text: validation.errors.to_h.to_s }] }
            end
          rescue StandardError => error
            { content: [{ type: 'text', text: "Error: #{error.message}" }], isError: true }
          end
        end

        def register_apply_config(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'apply_config',
            description: 'Apply a feed config to a URL and return RSS XML',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL' },
                config: {
                  type: 'object',
                  description: 'Feed configuration hash with selectors'
                }
              },
              required: %w[url config]
            }
          ) do |args, _server_context|
            url = args.fetch('url')
            config = args.fetch('config')

            feed_config = HashUtil.deep_symbolize_keys(config, context: 'config')
            feed_config[:channel] ||= {}
            feed_config[:channel][:url] ||= url

            rss = Html2rss.feed(feed_config)
            { content: [{ type: 'text', text: rss.to_s }] }
          rescue StandardError => error
            { content: [{ type: 'text', text: "Error: #{error.message}" }], isError: true }
          end
        end

        def register_resources(server) # rubocop:disable Metrics/MethodLength
          server.define_resource(
            uri: 'html2rss://schema',
            name: 'Configuration JSON Schema',
            description: 'Full JSON Schema for html2rss feed configurations',
            mime_type: 'application/json'
          ) do |_args, _server_context|
            schema = Html2rss::Config.json_schema_json(pretty: true)
            { content: [{ type: 'text', text: schema }] }
          end

          server.define_resource(
            uri: 'html2rss://extractors',
            name: 'Available Extractors',
            description: 'List of registered extractors with documentation'
          ) do |_args, _server_context|
            extractors = Html2rss::Selectors::Extractors::NAME_TO_CLASS.keys.map(&:to_s).sort
            { content: [{ type: 'text', text: JSON.pretty_generate(extractors) }] }
          end

          server.define_resource(
            uri: 'html2rss://strategies',
            name: 'Available Strategies',
            description: 'List of registered request strategies'
          ) do |_args, _server_context|
            strategies = Html2rss::RequestService.instance.strategy_names
            { content: [{ type: 'text', text: JSON.pretty_generate(strategies) }] }
          end
        end

        def register_prompts(server) # rubocop:disable Metrics/MethodLength
          server.define_prompt(
            name: 'scrape-webpage',
            description: 'Scrape a webpage and extract articles',
            arguments: [
              { name: 'url', description: 'URL to scrape', required: true }
            ]
          ) do |args, _server_context|
            url = args.fetch('url')
            {
              messages: [
                { role: 'user',
                  content: { type: 'text',
                             text: "Please scrape #{url} and return the articles found there as structured data." } }
              ]
            }
          end

          server.define_prompt(
            name: 'capture-feed-config',
            description: 'Analyze a URL and build a reusable html2rss feed config',
            arguments: [
              { name: 'url', description: 'URL to analyze', required: true }
            ]
          ) do |args, _server_context|
            url = args.fetch('url')
            {
              messages: [
                { role: 'user',
                  content: { type: 'text',
                             text: "Analyze #{url} and build an html2rss feed config that could be saved " \
                                   'to a YAML file and reused.' } }
              ]
            }
          end
        end

        def fetch_response(url, strategy) # rubocop:disable Metrics/MethodLength
          raw_config = Config.auto_source_config(
            url:,
            request_controls: Config::RequestControls.from_shortcut(strategy:)
          )
          raw_config[:strategy] = resolve_concrete_strategy(raw_config[:strategy] || strategy)
          config = Config.from_hash(raw_config)
          resources = FeedPipeline::RuntimePolicy.resources_for(config)
          session = RequestSession.build(
            config:,
            strategy: config.strategy,
            budget: resources.budget,
            policy: resources.policy
          )
          session.fetch_initial_response
        end

        def resolve_concrete_strategy(strategy)
          plan = FeedPipeline::StrategyPlan.resolve(strategy)
          plan.is_a?(FeedPipeline::StrategyPlan::Auto) ? :faraday : plan.strategy
        end

        def scraper_info(parsed)
          return { error: 'Response is not HTML' } unless parsed.is_a?(Nokogiri::HTML::Document)

          begin
            Html2rss::AutoSource::Scraper.from(parsed).map(&:name)
          rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
            { none_found: error.category.to_s }
          end
        end

        def sst_stats_from(response)
          return nil unless response.html_response?

          doc = sst_document(response)
          return nil unless doc

          { node_count: doc.node_count, degraded: doc.degraded }
        rescue StandardError
          nil
        end

        def sst_document(response)
          Html2rss::SST::Normalizer.call(response.body)
        rescue ArgumentError
          nil
        end

        def segment_stats(sst, url)
          segments = discover_segments(sst, url)
          return { found: 0 } if segments.empty?

          {
            found: segments.size,
            strategies: segments.map(&:strategy).uniq,
            sample_paths: segments.first(5).map { |s| s.root_node.tag_path }
          }
        end

        def discover_segments(sst, url)
          link_resolver = Scoring::LinkResolver.new(url)
          AutoSource::Segmenter.call(
            sst,
            base_url: url,
            strategy: :list,
            link_resolver:
          )
        rescue StandardError
          []
        end
      end
    end
  end
end
