# frozen_string_literal: true

module Html2rss
  module MCP
    module Server
      ##
      # MCP tool registration and outcome mapping over public html2rss APIs.
      module Tools # rubocop:disable Metrics/ModuleLength -- declarative registry + substantive handlers
        # Declarative MCP tool registrations consumed by {register_all}.
        TOOLS = [
          {
            name: 'scrape',
            kind: :url,
            description: 'One-shot article extraction as JSON Feed items. ' \
                         'Use when you need articles now without a saved config. ' \
                         'strategy "auto" triggers fallback chain (faraday → botasaurus) for JS-rendered sites.',
            input_schema: Contract::SCRAPE_INPUT_SCHEMA,
            handler: :scrape_outcome
          },
          {
            name: 'inspect',
            kind: :url,
            description: 'Diagnostic page analysis (scrapers, SST, segments, final URL, status, ' \
                         'rel=alternate feeds). Use recon for BUILD/DEFER/DROP verdict and native_feed preference.',
            input_schema: Contract::INSPECT_INPUT_SCHEMA,
            call: lambda { |url:, strategy: 'auto', **|
              Outcome.inspect(
                report: PageRecon::Diagnostics.call(
                  url:, strategy: Runtime.coerce_strategy(strategy), deep: false
                )
              )
            }
          },
          {
            name: 'recon',
            kind: :url,
            description: 'Curation verdict and native_feed preference for a URL. ' \
                         'Use after inspect when alternates warrant deeper recon, or when you need BUILD/DEFER/DROP.',
            input_schema: Contract::RECON_INPUT_SCHEMA,
            call: lambda { |url:, strategy: 'auto', **|
              Outcome.recon(result: Html2rss.recon(url, strategy: Runtime.coerce_strategy(strategy)))
            }
          },
          {
            name: 'batch_scrape',
            kind: :batch,
            batch_method: :batch_scrape,
            limit_default: 10,
            description: 'Scrape multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns structured JSON Feed items and extraction counts.',
            input_schema: Contract::BATCH_SCRAPE_INPUT_SCHEMA
          },
          {
            name: 'batch_inspect',
            kind: :batch,
            batch_method: :batch_inspect,
            description: 'Inspect multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns final redirected URLs, status codes, and rel="alternate" feeds.',
            input_schema: Contract::BATCH_INSPECT_INPUT_SCHEMA
          },
          {
            name: 'batch_recon',
            kind: :batch,
            batch_method: :batch_recon,
            description: 'Run recon across multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns verdict, native_feed, and surface classification per URL.',
            input_schema: Contract::BATCH_RECON_INPUT_SCHEMA
          },
          {
            name: 'capture',
            kind: :capture,
            description: 'Derive a reusable html2rss feed config from a URL. ' \
                         'Use when the goal is a durable YAML (then test → apply). ' \
                         'Returns YAML inside payload.yaml (same serializer as CLI capture). ' \
                         'Draft only — catalog feeds still need directory.topics and title/url; ' \
                         'enhance defaults from admission evidence (false when chrome drops are high). ' \
                         'Full schema options live in resource html2rss://schema.',
            input_schema: Contract::CAPTURE_INPUT_SCHEMA,
            handler: :capture_outcome
          },
          {
            name: 'validate',
            kind: :config_xor,
            description: 'Validate a feed config hash XOR yaml string against the html2rss JSON schema. ' \
                         'Call before test. Failures return isError with payload.errors. ' \
                         'Full schema lives in resource html2rss://schema.',
            input_schema: Contract::CONFIG_XOR_SCHEMA,
            annotations: Contract::ANNOTATIONS_VALIDATE,
            call: lambda { |config: nil, yaml: nil, **|
              validation = Html2rss::Config.validate(ConfigArgument.parse(config:, yaml:).config)
              Outcome.validate(errors: validation.success? ? nil : validation.errors.to_h)
            }
          },
          {
            name: 'test',
            kind: :config_xor,
            description: 'Validate schema and execute live extraction (asserting >= min_items items). ' \
                         'Call after capture or validate; on success next_step is apply. ' \
                         'Returns test summary in payload with sample items, timing, failure_kind, ' \
                         'and quality_report (warnings for duplicate URLs, junk titles, native feed). ' \
                         'Set strict_quality to fail on duplicate URLs, >50% junk titles, or short titles.',
            input_schema: Contract::TEST_INPUT_SCHEMA,
            call: lambda { |config: nil, yaml: nil, min_items: 1, strict_quality: false,
                              compare_enhance: false, **kwargs|
              feed_config = ConfigArgument.parse(config:, yaml:).config
              test_args = { min_items:, strict_quality:, compare_enhance: }
              test_args[:strategy] = Runtime.coerce_strategy(kwargs[:strategy]) if kwargs.key?(:strategy)
              test_result = Html2rss.test(feed_config, **test_args)
              Outcome.test(test_result)
            }
          },
          {
            name: 'apply',
            kind: :config_xor,
            description: 'Apply a validated feed config (hash XOR yaml) and return RSS XML in payload.rss. ' \
                         'isError when the feed has zero items (ship gate). payload.item_count is RSS item count. ' \
                         'Use after test succeeds.',
            input_schema: Contract::APPLY_INPUT_SCHEMA,
            handler: :apply_outcome
          }
        ].freeze

        class << self # rubocop:disable Metrics/ClassLength -- registration engine + handlers
          ##
          # Registers all MCP tools on +server+ via +registrar+ (Server.define_envelope_tool).
          #
          # @param server [::MCP::Server]
          # @param registrar [Proc]
          # @return [void]
          def register_all(server, registrar:)
            TOOLS.each { |entry| register_tool(server, registrar, entry) }
          end

          private

          def register_tool(server, registrar, entry)
            case entry[:kind]
            when :url then register_url_tool(server, registrar, entry)
            when :batch then register_batch_tool(server, registrar, entry)
            when :config_xor then register_config_xor_tool(server, registrar, entry)
            when :capture then register_capture_tool(server, registrar, entry)
            else raise ArgumentError, "unknown tool kind: #{entry[:kind].inspect}"
            end
          end

          def register_url_tool(server, registrar, entry)
            handler = entry[:handler] ? method(entry[:handler]) : entry[:call]
            registrar.call(
              server,
              name: entry[:name],
              description: entry[:description],
              input_schema: entry[:input_schema],
              annotations: entry.fetch(:annotations, Contract::ANNOTATIONS_OPEN_WORLD)
            ) do |**kwargs|
              handler.call(**tool_kwargs(kwargs))
            end
          end

          def register_batch_tool(server, registrar, entry) # rubocop:disable Metrics/MethodLength
            name = entry[:name]
            batch_method = entry[:batch_method]
            limit_default = entry[:limit_default]
            registrar.call(
              server,
              name:,
              description: entry[:description],
              input_schema: entry[:input_schema]
            ) do |urls:, strategy: 'auto', **kwargs|
              concurrency = kwargs.fetch(:concurrency, Batch::DEFAULT_CONCURRENCY)
              batch_args = { urls:, strategy: Runtime.coerce_strategy(strategy), concurrency: }
              batch_args[:limit] = kwargs.fetch(:limit, limit_default) unless limit_default.nil?
              Outcome.public_send(name, Batch.public_send(batch_method, **batch_args))
            end
          end

          def register_config_xor_tool(server, registrar, entry)
            handler = entry[:handler] ? method(entry[:handler]) : entry[:call]
            registrar.call(
              server,
              name: entry[:name],
              description: entry[:description],
              input_schema: entry[:input_schema],
              annotations: entry.fetch(:annotations, Contract::ANNOTATIONS_OPEN_WORLD)
            ) do |**kwargs|
              handler.call(**tool_kwargs(kwargs))
            end
          end

          def register_capture_tool(server, registrar, entry)
            handler = method(entry[:handler])
            registrar.call(
              server,
              name: entry[:name],
              description: entry[:description],
              input_schema: entry[:input_schema]
            ) do |**kwargs|
              handler.call(**tool_kwargs(kwargs))
            end
          end

          def tool_kwargs(inputs)
            args = inputs.dup
            args.delete(:server_context)
            args
          end

          def scrape_outcome(url:, strategy: 'auto', limit: 25, items_selector: nil)
            wire = Batch.scrape_wire(url:, strategy: Runtime.coerce_strategy(strategy), limit:, items_selector:)
            Outcome.scrape(
              items: wire[:items],
              requested_strategy: wire[:strategy],
              channel_title: wire[:channel_title],
              admission_drops: wire[:admission_drops],
              botasaurus_configured: Runtime.botasaurus_configured?
            )
          end

          def capture_outcome(url:, strategy: 'auto', items_selector: nil, force: false, topics: nil, title: nil, # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
                              summary: nil, enhance: nil, limit: nil, max_redirects: nil, max_requests: nil)
            plan = Runtime.coerce_strategy(strategy)
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
              native_feed: result.native_feed,
              suggested_channel_url: result.suggested_channel_url
            )
          end

          def apply_outcome(url:, config: nil, yaml: nil) # rubocop:disable Metrics/MethodLength -- quality_report + RSS payload
            feed_config = HashUtil.deep_dup(ConfigArgument.parse(config:, yaml:).config)
            feed_config[:channel] ||= {}
            feed_config[:channel][:url] ||= url
            feed_result, pipeline_outcome = extract_apply_feed(feed_config)
            rss = feed_result.to_rss
            quality_report = build_apply_quality_report(feed_config, feed_result, pipeline_outcome)
            Outcome.apply(
              rss: rss.to_s,
              item_count: rss.items.size,
              empty: feed_result.empty?,
              quality_report: quality_report.to_h
            )
          end

          def build_apply_quality_report(feed_config, feed_result, pipeline_outcome)
            rss = feed_result.to_rss
            Html2rss::Test.quality_report_for(
              rss.items,
              channel_url: feed_config.dig(:channel, :url).to_s,
              raw_config: feed_config,
              feed_result:,
              pipeline_outcome:,
              probe_native_feed: false
            )
          end

          def extract_apply_feed(feed_config)
            if apply_enhance_audit_needed?(feed_config)
              outcome, feed_result = FeedPipeline.new(feed_config).to_outcome_and_result
              [feed_result, outcome]
            else
              [Html2rss.feed_result(feed_config), nil]
            end
          end

          def apply_enhance_audit_needed?(feed_config)
            config = Config.from_hash(feed_config)
            return false unless config.selectors

            !!config.selectors.dig(:items, :enhance)
          end
        end
      end
    end
  end
end
