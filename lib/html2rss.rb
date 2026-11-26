# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  'cli' => 'CLI',
  'sst' => 'SST',
  'mcp' => 'MCP'
)
loader.setup

require 'logger'
require 'html2rss/defaults'

##
# The Html2rss namespace.
module Html2rss
  ##
  # Cheap diagnostics for a URL (final URL, status, alternates, surface).
  # Golden path step 1 (optional); use {.recon} for verdict and native_feed.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy (:auto, :default, :botasaurus)
  # @param deep [Boolean] when true and strategy is :auto, one Botasaurus hop if configured
  # @return [Html2rss::Curation::Inspect::Report]
  def self.inspect(url, strategy: :auto, deep: false, **)
    Curation::Inspect.call(url:, strategy:, deep:, **)
  end

  ##
  # Curation verdict and native_feed preference for a URL.
  # Golden path step 2 (optional); adds verdict beyond {.inspect}.
  #
  # @param url [String, Html2rss::Url] source page URL
  # @param strategy [Symbol] request strategy (:auto, :default, :botasaurus)
  # @return [Html2rss::Curation::Recon::Result]
  def self.recon(url, strategy: :auto, **)
    Curation::Recon.call(url, strategy:, **)
  end

  ##
  # Derives a reusable YAML-ready feed config from a URL.
  # Golden path step 3.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy (+:auto+, +:default+, +:botasaurus+)
  # @option options [String, nil] :items_selector optional CSS selector hint for items
  # @option options [Array<String>, nil] :topics optional directory topics override
  # @option options [String, nil] :title optional title override
  # @option options [String, nil] :summary optional summary override
  # @option options [Boolean] :force whether to ignore native feed detection
  # @option options [Boolean, nil] :enhance whether to force enhance: true
  # @option options [Integer, nil] :max_redirects optional redirect limit override
  # @option options [Integer, nil] :max_requests optional request budget override
  # @option options [Integer, nil] :limit max articles to keep
  # @option options [String, nil] :local_file_path optional local HTML file path
  # @return [Html2rss::Curation::Capture::CaptureResult]
  def self.capture(url, strategy: :auto, **)
    Curation::Capture.build(url, strategy:, **)
  end

  ##
  # Validates a config hash, YAML string, or file path against the schema.
  # Side door: schema-only check without live extraction.
  #
  # @param config_input [Hash, String]
  # @param feed_name [String, nil]
  # @param params [Hash]
  # @return [Html2rss::Config::ValidationReport]
  def self.validate(config_input, feed_name = nil, params: {})
    _raw, validation = Config.resolve_and_validate(config_input, feed_name:, params:)
    validation
  end

  ##
  # Validates schema and asserts live item extraction.
  # Golden path step 4.
  #
  # @param config_input [Hash, String] config hash, YAML string, or file path
  # @param feed_name [String, nil] optional feed name in multi-feed file
  # @param min_items [Integer] minimum required items, >= 0 (default: 1)
  # @param params [Hash] dynamic feed params
  # @param strategy [Symbol, nil] optional strategy override
  # @param strict_quality [Boolean] when true, fail on ship-quality audit thresholds
  # @param compare_enhance [Boolean] diagnostic enhance off vs on comparison on cached HTML
  # @param sample_limit [Integer] maximum number of +Result#items+, >= 0 (default: 3)
  # @return [Html2rss::Curation::Test::Result]
  def self.test(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil, strict_quality: false, # rubocop:disable Metrics/ParameterLists
                compare_enhance: false, sample_limit: 3)
    Curation::Test.call(config_input, feed_name, min_items:, params:, strategy:, strict_quality:, compare_enhance:,
                                                 sample_limit:)
  end

  ##
  # Ships RSS from a validated config. Golden path step 5.
  #
  # Returns the result even when the feed has no items (check {Apply::Result#empty?}); the CLI and
  # MCP surfaces turn an empty result into a failure. The result is not cacheable: cache
  # {.feed_result} instead.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @return [Html2rss::Curation::Apply::Result] responds to +to_rss+, +to_json_feed+, +status+, +empty?+
  def self.apply(raw_config)
    Curation::Apply.call(raw_config)
  end

  ##
  # One-shot auto-source scrape from a URL, without hand-written selectors.
  # Builds an auto_source config; FeedPipeline runs structured scrapers and, when needed, the SST
  # heuristic path (see lib/html2rss/auto_source/README.md).
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @option options [String, nil] :items_selector optional selector hint for item extraction
  # @option options [Integer, nil] :max_redirects optional redirect limit override
  # @option options [Integer, nil] :max_requests optional request budget override (nil derives it, max 10)
  # @option options [String, nil] :local_file_path optional local HTML file path
  # @option options [Integer, nil] :limit max articles to keep (default: {AutoSource::DEFAULT_LIMIT})
  # @option options [Boolean, nil] :keep_different_domain when set, overrides cleanup.keep_different_domain
  # @option options [Boolean, nil] :keep_sponsored when set, overrides cleanup.keep_sponsored
  # @return [Html2rss::FeedResult]
  def self.scrape(url, strategy: :auto, **)
    feed_result(Config::AutoSourceRequest.from_shortcut(url, strategy:, **).to_config)
  end

  ##
  # Scrapes multiple URLs in parallel using auto-source article discovery.
  #
  # @param urls [Enumerable<String>] list of URLs to scrape
  # @param strategy [Symbol] request strategy (:auto, :default, :botasaurus)
  # @param limit [Integer] max articles to keep per URL (default: 10)
  # @param concurrency [Integer] max worker threads (default: 5)
  # @return [Html2rss::Curation::Batch::BatchResult]
  def self.batch_scrape(urls, strategy: :auto, limit: 10, concurrency: Curation::Batch::DEFAULT_CONCURRENCY)
    Curation::Batch.batch_scrape(urls:, strategy:, limit:, concurrency:)
  end

  ##
  # Inspects multiple URLs in parallel with per-URL error isolation.
  #
  # @param urls [Enumerable<String>] list of URLs to inspect
  # @param strategy [Symbol] request strategy (:auto, :default, :botasaurus)
  # @param concurrency [Integer] max worker threads (default: 5)
  # @return [Html2rss::Curation::Batch::BatchResult]
  def self.batch_inspect(urls, strategy: :auto, concurrency: Curation::Batch::DEFAULT_CONCURRENCY)
    Curation::Batch.batch_inspect(urls:, strategy:, concurrency:)
  end

  ##
  # Runs recon across multiple URLs in parallel with per-URL error isolation.
  #
  # @param urls [Enumerable<String>] list of URLs to recon
  # @param strategy [Symbol] request strategy (:auto, :default, :botasaurus)
  # @param concurrency [Integer] max worker threads (default: 5)
  # @option options [String, nil] :cache_dir optional HTML cache directory
  # @return [Html2rss::Curation::Batch::BatchResult]
  def self.batch_recon(urls, strategy: :auto, concurrency: Curation::Batch::DEFAULT_CONCURRENCY, **)
    Curation::Batch.batch_recon(urls:, strategy:, concurrency:, **)
  end

  ##
  # Exports the configuration JSON Schema as JSON string.
  #
  # @param pretty [Boolean] whether to pretty-print JSON
  # @return [String]
  def self.schema_json(pretty: true)
    Config::Schema.json_schema_json(pretty:)
  end

  ##
  # Loads a feed configuration from YAML.
  #
  # @param file [String] path to the YAML file
  # @param feed_name [String, nil] optional feed name inside a multi-feed config
  # @return [Hash{Symbol => Object}] loaded configuration hash
  def self.config_from_yaml_file(file, feed_name = nil)
    Config.load_yaml(file, feed_name)
  end

  ##
  # Returns an opaque, Marshal-cacheable result of one scrape.
  #
  # Prefer this when the same scrape must render as RSS and JSON Feed (e.g. web cache).
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @return [Html2rss::FeedResult]
  def self.feed_result(raw_config)
    FeedPipeline.new(raw_config).to_result
  end

  ##
  # Returns an RSS object generated from the provided configuration.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @return [RSS::Rss] generated RSS feed
  def self.feed(raw_config)
    feed_result(raw_config).to_rss
  end

  # rubocop:disable-next ThreadSafety/ClassInstanceVariable
  class << self
    ##
    # @return [Html2rss::Defaults] the global defaults instance
    def defaults
      @defaults ||= Defaults.new.freeze
    end

    ##
    # Configures global library defaults.
    #
    # @yieldparam config [Html2rss::Defaults]
    # @return [Html2rss::Defaults] the frozen defaults
    def configure
      config = defaults.dup
      yield config
      @defaults = config.freeze
    end

    ##
    # @return [Logger] the logger
    def logger
      defaults.logger
    end

    ##
    # @param logger [Logger] the new logger
    def logger=(logger)
      configure { |config| config.logger = logger }
    end

    ##
    # Resets the global defaults (mainly for testing).
    #
    # @return [void]
    def reset_defaults!
      @defaults = nil
      logger.level = defaults.log_level
    end
  end

  logger.level = defaults.log_level
end

loader.eager_load
