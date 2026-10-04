# frozen_string_literal: true

module Html2rss
  module MCP
    module Server
      ##
      # MCP tool registry: typed {Tool} values over public html2rss APIs.
      module Tools # rubocop:disable Metrics/ModuleLength -- declarative registry + substantive handlers
        Tool = Data.define(:name, :title, :description, :input_schema, :annotations, :call)

        ##
        # One published MCP tool. +call+ is a lambda with explicit keyword defaults.
        # +annotations+ is {Contract::ANNOTATIONS_OPEN_WORLD} unless a tool overrides it.
        class Tool # rubocop:disable Lint/EmptyClass -- Data members only; handlers are +call+ lambdas
        end

        # Published MCP tools consumed by {Server.register_tools}.
        TOOLS = [
          Tool.new(
            name: 'scrape',
            title: 'Scrape',
            description: 'One-shot article extraction as JSON Feed items. ' \
                         'Use when you need articles now without a saved config. ' \
                         'strategy "auto" triggers fallback chain (default → botasaurus) for JS-rendered sites.',
            input_schema: Contract::SCRAPE_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |url:, strategy: 'auto', limit: 25, items_selector: nil, **|
              scrape_outcome(url:, strategy:, limit:, items_selector:)
            }
          ),
          Tool.new(
            name: 'inspect',
            title: 'Inspect',
            description: 'Diagnostic page analysis (scrapers, SST, segments, final URL, status, ' \
                         'rel=alternate feeds). Use recon for BUILD/DEFER/DROP verdict and native_feed preference.',
            input_schema: Contract::INSPECT_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |url:, strategy: 'auto', **|
              Outcome.inspect(
                report: PageRecon::Diagnostics.call(
                  url:, strategy: Runtime.coerce_strategy(strategy), deep: false
                )
              )
            }
          ),
          Tool.new(
            name: 'recon',
            title: 'Recon',
            description: 'Curation verdict and native_feed preference for a URL. ' \
                         'Use after inspect when alternates warrant deeper recon, or when you need BUILD/DEFER/DROP.',
            input_schema: Contract::RECON_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |url:, strategy: 'auto', **|
              Outcome.recon(result: Html2rss.recon(url, strategy: Runtime.coerce_strategy(strategy)))
            }
          ),
          Tool.new(
            name: 'batch_scrape',
            title: 'Batch scrape',
            description: 'Scrape multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns structured JSON Feed items and extraction counts.',
            input_schema: Contract::BATCH_SCRAPE_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |urls:, strategy: 'auto', concurrency: Batch::DEFAULT_CONCURRENCY, limit: 10, **|
              Outcome.batch_scrape(
                Batch.batch_scrape(urls:, strategy: Runtime.coerce_strategy(strategy), concurrency:, limit:)
              )
            }
          ),
          Tool.new(
            name: 'batch_inspect',
            title: 'Batch inspect',
            description: 'Inspect multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns final redirected URLs, status codes, and rel="alternate" feeds.',
            input_schema: Contract::BATCH_INSPECT_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |urls:, strategy: 'auto', concurrency: Batch::DEFAULT_CONCURRENCY, **|
              Outcome.batch_inspect(
                Batch.batch_inspect(urls:, strategy: Runtime.coerce_strategy(strategy), concurrency:)
              )
            }
          ),
          Tool.new(
            name: 'batch_recon',
            title: 'Batch recon',
            description: 'Run recon across multiple URLs in parallel with per-URL error isolation. ' \
                         'Returns verdict, native_feed, and surface classification per URL.',
            input_schema: Contract::BATCH_RECON_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |urls:, strategy: 'auto', concurrency: Batch::DEFAULT_CONCURRENCY, **|
              Outcome.batch_recon(
                Batch.batch_recon(urls:, strategy: Runtime.coerce_strategy(strategy), concurrency:)
              )
            }
          ),
          Tool.new(
            name: 'capture',
            title: 'Capture',
            description: 'Derive a reusable html2rss feed config from a URL. ' \
                         'Use when the goal is a durable YAML (then test → apply). ' \
                         'Returns YAML inside payload.yaml (same serializer as CLI capture). ' \
                         'Draft only — catalog feeds still need directory.topics and title/url; ' \
                         'enhance defaults from admission evidence (false when chrome drops are high). ' \
                         'Full schema options live in resource html2rss://schema.',
            input_schema: Contract::CAPTURE_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |url:, strategy: 'auto', items_selector: nil, force: false, topics: nil, title: nil,
                              summary: nil, enhance: nil, limit: nil, max_redirects: nil, max_requests: nil, **|
              capture_outcome(url:, strategy:, items_selector:, force:, topics:, title:, summary:,
                              enhance:, limit:, max_redirects:, max_requests:)
            }
          ),
          Tool.new(
            name: 'validate',
            title: 'Validate',
            description: 'Validate a feed config hash XOR yaml string against the html2rss JSON schema. ' \
                         'Call before test. Failures return isError with payload.issues. ' \
                         'Full schema lives in resource html2rss://schema.',
            input_schema: Contract::CONFIG_XOR_SCHEMA,
            annotations: Contract::ANNOTATIONS_VALIDATE,
            call: lambda { |config: nil, yaml: nil, **|
              Outcome.validate(report: Html2rss::Config.validate(ConfigArgument.parse(config:, yaml:).config))
            }
          ),
          Tool.new(
            name: 'test',
            title: 'Test',
            description: 'Validate schema and execute live extraction (asserting >= min_items items). ' \
                         'Call after capture or validate; on success next_step is apply. ' \
                         'Returns test summary in payload with sample items, timing, failure_kind, ' \
                         'and quality_report (warnings for duplicate URLs, junk titles, native feed). ' \
                         'Set strict_quality to fail on duplicate URLs, >50% junk titles, or short titles.',
            input_schema: Contract::TEST_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |config: nil, yaml: nil, min_items: 1, strict_quality: false,
                              compare_enhance: false, **kwargs|
              feed_config = ConfigArgument.parse(config:, yaml:).config
              test_args = { min_items:, strict_quality:, compare_enhance: }
              test_args[:strategy] = Runtime.coerce_strategy(kwargs[:strategy]) if kwargs.key?(:strategy)
              Outcome.test(Html2rss.test(feed_config, **test_args))
            }
          ),
          Tool.new(
            name: 'apply',
            title: 'Apply',
            description: 'Apply a validated feed config (hash XOR yaml) and return RSS XML in payload.rss. ' \
                         'isError when the feed has zero items (ship gate). payload.item_count is RSS item count. ' \
                         'Use after test succeeds.',
            input_schema: Contract::APPLY_INPUT_SCHEMA,
            annotations: Contract::ANNOTATIONS_OPEN_WORLD,
            call: lambda { |url:, config: nil, yaml: nil, **|
              apply_outcome(url:, config:, yaml:)
            }
          )
        ].freeze

        class << self
          ##
          # @api private
          # @param url [String]
          # @param strategy [String, Symbol]
          # @param limit [Integer]
          # @param items_selector [String, nil]
          # @return [Outcome]
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

          ##
          # @api private
          # @param url [String]
          # @param strategy [String, Symbol]
          # @param items_selector [String, nil]
          # @param force [Boolean]
          # @param topics [Array<String>, nil]
          # @param title [String, nil]
          # @param summary [String, nil]
          # @param enhance [Boolean, nil]
          # @param limit [Integer, nil]
          # @param max_redirects [Integer, nil]
          # @param max_requests [Integer, nil]
          # @return [Outcome]
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

          ##
          # @api private
          # @param url [String]
          # @param config [Hash, nil]
          # @param yaml [String, nil]
          # @return [Outcome]
          def apply_outcome(url:, config: nil, yaml: nil)
            feed_config = HashUtil.deep_dup(ConfigArgument.parse(config:, yaml:).config)
            feed_config[:channel] ||= {}
            feed_config[:channel][:url] ||= url
            outcome, feed_result = FeedPipeline.new(feed_config).to_outcome_and_result
            apply_feed_outcome(feed_config, feed_result, outcome)
          end

          private

          def apply_feed_outcome(feed_config, feed_result, outcome) # rubocop:disable Metrics/MethodLength -- quality_report + RSS payload
            rss = feed_result.to_rss
            quality_report = Html2rss::Test.quality_report_for(
              rss.items,
              channel_url: feed_config.dig(:channel, :url).to_s,
              config: Html2rss::Config.from_hash(feed_config),
              feed_result:,
              pipeline_outcome: outcome,
              probe_native_feed: false
            )
            Outcome.apply(
              rss: rss.to_s,
              item_count: rss.items.size,
              empty: feed_result.empty?,
              quality_report: quality_report.to_h
            )
          end
        end
      end
    end
  end
end
