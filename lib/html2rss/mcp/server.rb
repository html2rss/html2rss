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
        # @param transport [Symbol] +:stdio+ or +:http+
        # @param port [Integer] port for HTTP transport
        def start(transport: :stdio, port: 8080)
          app = build

          case transport
          when :stdio
            ::MCP::Server::Transports::StdioTransport.new(app).open
          when :http
            start_http(app, port:)
          else
            raise ArgumentError, "Unknown transport: #{transport.inspect}"
          end
        end

        ##
        # Builds the configured MCP protocol server (tools/resources/prompts).
        #
        # @return [::MCP::Server]
        def build
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
          text_response("Error: #{error.message}", error: true)
        end

        private

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

            1. Need articles now (no saved config)? → scrape_url
               - strategy "auto" triggers faraday → botasaurus fallback chain for JS-rendered sites.
               - If botasaurus is unconfigured and auto fails, try explicit "faraday" or set up Botasaurus.
            2. Need a reusable feed YAML/config? → capture_config, then validate_config, then apply_config
            3. Debugging why scrape/capture is weak? → inspect_url (scrapers/SST/segments/blocked_surface), then retry scrape/capture
            4. Have a config already? → validate_config (must succeed) → apply_config for RSS XML
            5. Schema / extractor / strategy lists → resources html2rss://schema|extractors|strategies

            Prefer capture_config when the goal is a durable config; prefer scrape_url for one-shot extraction.
            Botasaurus needs BOTASAURUS_SCRAPER_URL (see docker-compose.botasaurus.yml).
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
            feed = Html2rss.auto_json_feed(url, strategy: plan, limit:, items_selector:)
            items = feed[:items] || []
            Server.text_response(JSON.generate(items), meta: {
                                   total: items.size,
                                   strategy: plan.to_s,
                                   channel_title: feed[:title]
                                 })
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_inspect_url(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'inspect_url',
            description: 'Diagnostic page analysis (scrapers, SST, segments). ' \
                         'Use when scrape_url/capture_config returns little and you need to see why.',
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
                         'Use when the goal is a durable YAML/config (then validate_config). ' \
                         'Returns config plus quality meta (articles_count, selectors presence). ' \
                         'Full schema options live in resource html2rss://schema.',
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
            selectors = result.config[:selectors]
            Server.text_response(
              JSON.pretty_generate(result.config),
              meta: {
                articles_count: result.articles_count,
                channel_title: result.channel_title,
                has_selectors: !selectors.nil? && !selectors.empty?,
                strategy: plan.to_s
              }
            )
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_validate_config(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'validate_config',
            description: 'Validate a feed config hash against the html2rss JSON schema. ' \
                         'Call before apply_config. Failures return isError with structured error details. ' \
                         'Full schema lives in resource html2rss://schema.',
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
          ) do |server_context:, config:| # rubocop:disable Lint/UnusedBlockArgument
            config_hash = HashUtil.deep_symbolize_keys(config, context: 'config')
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

        def register_apply_config(server) # rubocop:disable Metrics/MethodLength
          server.define_tool(
            name: 'apply_config',
            description: 'Apply a validated feed config and return RSS XML. ' \
                         'Use after validate_config succeeds.',
            input_schema: {
              type: 'object',
              properties: {
                url: { type: 'string', description: 'Source page URL (fills channel.url if missing)' },
                config: {
                  type: 'object',
                  description: 'Feed configuration hash with selectors'
                }
              },
              required: %w[url config]
            }
          ) do |server_context:, url:, config:| # rubocop:disable Lint/UnusedBlockArgument
            feed_config = HashUtil.deep_symbolize_keys(config, context: 'config')
            feed_config[:channel] ||= {}
            feed_config[:channel][:url] ||= url

            rss = Html2rss.feed(feed_config)
            Server.text_response(rss.to_s)
          rescue StandardError => error
            Server.error_response(error)
          end
        end

        def register_resources(server) # rubocop:disable Metrics/MethodLength
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
        end

        def register_prompts(server) # rubocop:disable Metrics/MethodLength
          server.define_prompt(
            name: 'scrape-webpage',
            description: 'Guided one-shot scrape: scrape_url then inspect/retry with botasaurus if needed',
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
                      Scrape #{url} with the scrape_url tool (strategy auto first).
                      If articles are empty or look JS-gated, call inspect_url, then scrape_url again with strategy botasaurus.
                      Return the structured articles JSON.
                    MSG
                  }
                }
              ]
            }
          end

          server.define_prompt(
            name: 'capture-feed-config',
            description: 'Guided capture → validate → optional apply for a reusable feed config',
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
                      1) capture_config — check _meta.articles_count and has_selectors
                      2) If weak, inspect_url and/or retry capture_config with strategy botasaurus
                      3) validate_config on the config (must not be isError)
                      4) Optionally apply_config to confirm RSS XML
                      Return the validated config hash suitable for YAML.
                    MSG
                  }
                }
              ]
            }
          end
        end
      end

      ##
      # Diagnostic inspect path (not Capture ownership). Fetches once for SST/scraper stats.
      module Inspect # rubocop:disable Metrics/ModuleLength -- diagnostic helpers stay co-located
        module_function

        ##
        # @param url [String]
        # @param strategy [String, Symbol]
        # @return [Hash]
        def call(url:, strategy: :auto) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          resolved = FeedPipeline::StrategyPlan.concrete_for_diagnostic(strategy)
          response = fetch_response(url, resolved)
          parsed = response.parsed_body

          result = {
            url:,
            strategy: resolved,
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

          blocked = Html2rss::RequestService::BlockedSurface.interstitial_signature_for(response.body)
          result[:blocked_surface] = blocked[:key].to_s if blocked
          result[:xhr_capture] = xhr_capture_info(response) if resolved == :botasaurus

          result
        end

        ##
        # @param response [Html2rss::RequestService::Response]
        # @return [Hash] redacted XHR capture diagnostics (no query strings)
        def xhr_capture_info(response)
          captured = response.captured_responses
          {
            count: captured.size,
            sample_endpoints: captured.first(5).filter_map { |entry| redacted_endpoint(entry) },
            candidate_articles: captured.any? { |entry| xhr_candidate_articles?(entry) }
          }
        end
        module_function :xhr_capture_info

        ##
        # @param entry [Hash] captured response hash
        # @return [String, nil] scheme+host+path only
        def redacted_endpoint(entry)
          raw = entry['url'] || entry[:url]
          return unless raw

          uri = URI.parse(raw.to_s)
          return unless uri.scheme && uri.host

          "#{uri.scheme}://#{uri.host}#{uri.path}"
        rescue URI::InvalidURIError
          nil
        end
        module_function :redacted_endpoint

        ##
        # @param entry [Hash] captured response hash
        # @return [Boolean]
        def xhr_candidate_articles?(entry)
          body = entry['body'] || entry[:body]
          return false unless body.is_a?(String)

          document = JSON.parse(body, symbolize_names: true)
          AutoSource::Scraper::JsonState::CandidateDetector.candidate_array?(document)
        rescue JSON::ParserError
          false
        end
        module_function :xhr_candidate_articles?

        ##
        # @param url [String]
        # @param strategy [Symbol]
        # @return [Html2rss::RequestService::Response]
        def fetch_response(url, strategy) # rubocop:disable Metrics/MethodLength -- session construction
          raw_config = Config.auto_source_config(
            url:,
            request_controls: Config::RequestControls.from_shortcut(strategy:)
          )
          raw_config[:strategy] = strategy
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
        module_function :fetch_response

        ##
        # @param parsed [Object] parsed response body
        # @return [Array<String>, Hash]
        def scraper_info(parsed)
          return { error: 'Response is not HTML' } unless parsed.is_a?(Nokogiri::HTML::Document)

          begin
            Html2rss::AutoSource::Scraper.from(parsed).map(&:name)
          rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
            { none_found: error.category.to_s }
          end
        end
        module_function :scraper_info

        ##
        # @param response [Html2rss::RequestService::Response]
        # @return [Hash, nil]
        def sst_stats_from(response)
          return nil unless response.html_response?

          doc = sst_document(response)
          return nil unless doc

          { node_count: doc.node_count, degraded: doc.degraded }
        rescue StandardError
          nil
        end
        module_function :sst_stats_from

        ##
        # @param response [Html2rss::RequestService::Response]
        # @return [Html2rss::SST::Document, nil]
        def sst_document(response)
          Html2rss::SST::Normalizer.call(response.body)
        rescue ArgumentError
          nil
        end
        module_function :sst_document

        ##
        # @param sst [Html2rss::SST::Document]
        # @param url [String]
        # @return [Hash]
        def segment_stats(sst, url)
          segments = discover_segments(sst, url)
          return { found: 0 } if segments.empty?

          {
            found: segments.size,
            strategies: segments.map(&:strategy).uniq,
            sample_paths: segments.first(5).map { |s| s.root_node.tag_path }
          }
        end
        module_function :segment_stats

        ##
        # @param sst [Html2rss::SST::Document]
        # @param url [String]
        # @return [Array]
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
        module_function :discover_segments
      end
    end
  end
end
