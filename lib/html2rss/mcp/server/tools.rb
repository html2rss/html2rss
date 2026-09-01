# frozen_string_literal: true

module Html2rss
  module MCP
    module Server
      ##
      # MCP tool registration and outcome mapping over public html2rss APIs.
      module Tools # rubocop:disable Metrics/ModuleLength
        class << self # rubocop:disable Metrics/ClassLength
          ##
          # Registers all MCP tools on +server+ via +registrar+ ({Server.define_envelope_tool}).
          #
          # @param server [::MCP::Server]
          # @param registrar [Proc]
          # @return [void]
          def register_all(server, registrar:)
            register_scrape(server, registrar)
            register_inspect(server, registrar)
            register_recon(server, registrar)
            register_batch_scrape(server, registrar)
            register_batch_inspect(server, registrar)
            register_batch_recon(server, registrar)
            register_capture(server, registrar)
            register_validate(server, registrar)
            register_test(server, registrar)
            register_apply(server, registrar)
          end

          private

          def register_url_tool(server, registrar, name:, description:, input_schema:)
            registrar.call(
              server,
              name:,
              description:,
              input_schema:
            ) do |server_context:, **kwargs| # rubocop:disable Lint/UnusedBlockArgument
              yield(**kwargs)
            end
          end

          def register_batch_tool(server, registrar, name:, description:, input_schema:, batch_method:, # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
                                  limit_default: nil)
            registrar.call(
              server,
              name:,
              description:,
              input_schema:
            ) do |server_context:, urls:, strategy: 'auto', **kwargs| # rubocop:disable Lint/UnusedBlockArgument
              concurrency = kwargs.fetch(:concurrency, Batch::DEFAULT_CONCURRENCY)
              batch_args = { urls:, strategy:, concurrency: }
              batch_args[:limit] = kwargs.fetch(:limit, limit_default) unless limit_default.nil?
              Outcome.public_send(name, Batch.public_send(batch_method, **batch_args))
            end
          end

          def register_scrape(server, registrar) # rubocop:disable Metrics/MethodLength
            register_url_tool(
              server,
              registrar,
              name: 'scrape',
              description: 'One-shot article extraction as JSON Feed items. ' \
                           'Use when you need articles now without a saved config. ' \
                           'strategy "auto" triggers fallback chain (faraday → botasaurus) for JS-rendered sites.',
              input_schema: Contract::SCRAPE_INPUT_SCHEMA
            ) do |url:, strategy: 'auto', limit: 25, items_selector: nil|
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

          def register_inspect(server, registrar) # rubocop:disable Metrics/MethodLength
            register_url_tool(
              server,
              registrar,
              name: 'inspect',
              description: 'Diagnostic page analysis (scrapers, SST, segments) plus recon: ' \
                           'final_url, status, scheme_downgrade, rel=alternate RSS/Atom feeds. ' \
                           'Use when scrape/capture is weak or you need those recon facts.',
              input_schema: Contract::INSPECT_INPUT_SCHEMA
            ) do |url:, strategy: 'auto'|
              Outcome.inspect(report: PageRecon::Diagnostics.call(url:, strategy:))
            end
          end

          def register_recon(server, registrar)
            register_url_tool(
              server,
              registrar,
              name: 'recon',
              description: 'Curation verdict and native_feed preference for a URL. ' \
                           'Use after inspect when alternates warrant deeper recon, or when you need BUILD/DEFER/DROP.',
              input_schema: Contract::RECON_INPUT_SCHEMA
            ) do |url:, strategy: 'auto'|
              Outcome.recon(result: Html2rss.recon(url, strategy:))
            end
          end

          def register_batch_scrape(server, registrar)
            register_batch_tool(
              server,
              registrar,
              name: 'batch_scrape',
              batch_method: :batch_scrape,
              limit_default: 10,
              description: 'Scrape multiple URLs in parallel with per-URL error isolation. ' \
                           'Returns structured JSON Feed items and extraction counts.',
              input_schema: Contract::BATCH_SCRAPE_INPUT_SCHEMA
            )
          end

          def register_batch_inspect(server, registrar)
            register_batch_tool(
              server,
              registrar,
              name: 'batch_inspect',
              batch_method: :batch_inspect,
              description: 'Inspect multiple URLs in parallel with per-URL error isolation. ' \
                           'Returns final redirected URLs, status codes, and rel="alternate" feeds.',
              input_schema: Contract::BATCH_INSPECT_INPUT_SCHEMA
            )
          end

          def register_batch_recon(server, registrar)
            register_batch_tool(
              server,
              registrar,
              name: 'batch_recon',
              batch_method: :batch_recon,
              description: 'Run recon across multiple URLs in parallel with per-URL error isolation. ' \
                           'Returns verdict, native_feed, and surface classification per URL.',
              input_schema: Contract::BATCH_RECON_INPUT_SCHEMA
            )
          end

          def register_capture(server, registrar) # rubocop:disable Metrics/MethodLength
            registrar.call(
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

          def capture_outcome(url:, strategy:, items_selector:, force: false, topics: nil, title: nil, # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
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

          def register_validate(server, registrar) # rubocop:disable Metrics/MethodLength
            registrar.call(
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

          def register_test(server, registrar)
            registrar.call(
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

          def register_apply(server, registrar)
            registrar.call(
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

          def botasaurus_configured?
            !ENV['BOTASAURUS_SCRAPER_URL'].to_s.strip.empty?
          end
        end
      end
    end
  end
end
