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
require 'forwardable'
require 'html2rss/defaults'

##
# The Html2rss namespace.
module Html2rss # rubocop:disable Metrics/ModuleLength
  ##
  # The logger instance.
  module Log
    class << self
      extend Forwardable

      def_delegator 'Html2rss', :logger
      def_delegators :logger, :debug, :info, :warn, :error, :fatal, :unknown, :level, :level=, :formatter, :formatter=
    end
  end

  ##
  # Cheap diagnostics for a URL (final URL, status, alternates, surface).
  # Golden path step 1 (optional); use {.recon} for verdict and native_feed.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
  # @return [Html2rss::PageRecon::Diagnostics::Report]
  def self.inspect(url, strategy: :auto, **)
    PageRecon::Diagnostics.call(url:, strategy:, **)
  end

  ##
  # Curation verdict and native_feed preference for a URL.
  # Golden path step 2 (optional); adds verdict beyond {.inspect}.
  #
  # @param url [String, Html2rss::Url] source page URL
  # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
  # @return [Html2rss::Recon::Result]
  def self.recon(url, strategy: :auto, **)
    Recon.call(url, strategy:, **)
  end

  ##
  # Derives a reusable YAML-ready feed config from a URL.
  # Golden path step 3.
  #
  # @param url [String] source page URL
  # @return [Html2rss::Capture::CaptureResult]
  def self.capture(url, strategy: :auto, **)
    Capture.build(url, strategy:, **)
  end

  ##
  # Validates a config hash, YAML string, or file path against the schema.
  # Side door: schema-only check without live extraction.
  #
  # @param config_input [Hash, String]
  # @return [Dry::Validation::Result, Html2rss::Config::ValidationResult]
  def self.validate(config_input, feed_name = nil, params: {})
    _raw, validation = Config.resolve_and_validate(config_input, feed_name:, params:)
    validation
  end

  ##
  # Validates schema and asserts live item extraction.
  # Golden path step 4.
  #
  # @param config_input [Hash, String] config hash, YAML string, or file path
  # @return [Html2rss::Test::Result]
  def self.test(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil)
    Test.call(config_input, feed_name, min_items:, params:, strategy:)
  end

  ##
  # Ships RSS from a validated config (user-facing verb for {.feed_result}).
  # Golden path step 5.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @return [Html2rss::FeedResult]
  def self.apply(raw_config)
    feed_result(raw_config)
  end

  # rubocop:disable Metrics/ParameterLists

  ##
  # One-shot auto-source scrape from a URL (user-facing verb for {.auto_feed_result}).
  #
  # @param url [String] source page URL
  # @return [Html2rss::FeedResult]
  def self.scrape(url,
                  strategy: :auto,
                  items_selector: nil,
                  max_redirects: nil,
                  max_requests: 4,
                  local_file_path: nil,
                  limit: nil)
    auto_feed_result(url, strategy:, items_selector:, max_redirects:, max_requests:,
                          local_file_path:, limit:)
  end

  ##
  # Scrapes multiple URLs in parallel using auto-source article discovery.
  #
  # @param urls [Enumerable<String>] list of URLs to scrape
  # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
  # @param limit [Integer] max articles to keep per URL (default: 10)
  # @param concurrency [Integer] max worker threads (default: 5)
  # @return [Html2rss::Batch::BatchResult]
  def self.batch_scrape(urls, strategy: :auto, limit: 10, concurrency: Batch::DEFAULT_CONCURRENCY)
    Batch.batch_scrape(urls:, strategy:, limit:, concurrency:)
  end

  ##
  # Inspects multiple URLs in parallel with per-URL error isolation.
  #
  # @param urls [Enumerable<String>] list of URLs to inspect
  # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
  # @param concurrency [Integer] max worker threads (default: 5)
  # @return [Html2rss::Batch::BatchResult]
  def self.batch_inspect(urls, strategy: :auto, concurrency: Batch::DEFAULT_CONCURRENCY)
    Batch.batch_inspect(urls:, strategy:, concurrency:)
  end

  ##
  # Runs recon across multiple URLs in parallel with per-URL error isolation.
  #
  # @param urls [Enumerable<String>] list of URLs to recon
  # @param strategy [Symbol] request strategy (:auto, :faraday, :botasaurus)
  # @param concurrency [Integer] max worker threads (default: 5)
  # @option options [String, nil] :cache_dir optional HTML cache directory
  # @return [Html2rss::Batch::BatchResult]
  def self.batch_recon(urls, strategy: :auto, concurrency: Batch::DEFAULT_CONCURRENCY, **)
    Batch.batch_recon(urls:, strategy:, concurrency:, **)
  end

  # rubocop:enable Metrics/ParameterLists

  ##
  # Exports the configuration JSON Schema as JSON string.
  #
  # @param pretty [Boolean] whether to pretty-print JSON
  # @return [String]
  def self.schema_json(pretty: true)
    Config.json_schema_json(pretty:)
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

  ##
  # Returns a JSONFeed 1.1 hash generated from the provided configuration.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @param feed_url [String, nil] optional self URL for the feed (JSON Feed +feed_url+)
  # @return [Hash] JSONFeed-compliant hash
  def self.json_feed(raw_config, feed_url: nil)
    feed_result(raw_config).to_json_feed(feed_url:)
  end

  # rubocop:disable Metrics/ParameterLists

  ##
  # Scrapes the provided URL without hand-written selectors and returns {FeedResult}.
  #
  # Prefer this when callers need {FeedResult#status} (MCP envelope payload, CLI +--explain+).
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer] optional request budget override (default: 4 for sitemap sub-fetches)
  # @param local_file_path [String, nil] optional local HTML file path
  # @param limit [Integer, nil] max articles to keep (default: {AutoSource::DEFAULT_LIMIT})
  # @return [Html2rss::FeedResult]
  def self.auto_feed_result(url,
                            strategy: :auto,
                            items_selector: nil,
                            max_redirects: nil,
                            max_requests: 4,
                            local_file_path: nil,
                            limit: nil)
    feed_result(build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:,
                                         local_file_path:, limit:))
  end

  ##
  # Scrapes the provided URL without hand-written selectors and returns an RSS object.
  #
  # Builds an auto_source config, then FeedPipeline runs structured scrapers and
  # (when needed) the SST heuristic path — see lib/html2rss/auto_source/README.md.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer] optional request budget override (default: 4 for sitemap sub-fetches)
  # @param local_file_path [String, nil] optional local HTML file path
  # @param limit [Integer, nil] max articles to keep (default: {AutoSource::DEFAULT_LIMIT})
  # @return [RSS::Rss] generated RSS feed
  def self.auto_source(url,
                       strategy: :auto,
                       items_selector: nil,
                       max_redirects: nil,
                       max_requests: 4,
                       local_file_path: nil,
                       limit: nil)
    auto_feed_result(url, strategy:, items_selector:, max_redirects:, max_requests:,
                          local_file_path:, limit:).to_rss
  end

  ##
  # Scrapes the provided URL without hand-written selectors and returns a JSONFeed 1.1 hash.
  #
  # Same auto_source pipeline as {.auto_source}; see lib/html2rss/auto_source/README.md.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer] optional request budget override (default: 4 for sitemap sub-fetches)
  # @param local_file_path [String, nil] optional local HTML file path
  # @param limit [Integer, nil] max articles to keep (default: {AutoSource::DEFAULT_LIMIT})
  # @return [Hash] JSONFeed-compliant hash
  def self.auto_json_feed(url,
                          strategy: :auto,
                          items_selector: nil,
                          max_redirects: nil,
                          max_requests: 4,
                          local_file_path: nil,
                          limit: nil)
    auto_feed_result(url, strategy:, items_selector:, max_redirects:, max_requests:,
                          local_file_path:, limit:).to_json_feed
  end

  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable ThreadSafety/ClassInstanceVariable
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
    # @return [Object] the logger
    def logger
      defaults.logger
    end

    ##
    # @param logger [Object] the new logger
    def logger=(logger)
      configure { |config| config.logger = logger }
    end

    private

    ##
    # Resets the global defaults (mainly for testing).
    #
    # @return [void]
    def reset_defaults!
      @defaults = nil
      logger.level = defaults.log_level if logger.respond_to?(:level=)
    end
  end
  # rubocop:enable ThreadSafety/ClassInstanceVariable

  class << self
    private

    # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
    def build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:,
                                 local_file_path: nil, limit: nil)
      config = Config.auto_source_config(
        url:,
        items_selector:,
        request_controls: Config::RequestControls.from_shortcut(strategy:, max_redirects:, max_requests:),
        limit:
      )
      if local_file_path
        config[:request] ||= {}
        config[:request][:local_file_path] = local_file_path
      end
      config
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength
  end

  logger.level = defaults.log_level if logger.respond_to?(:level=)
end

loader.eager_load
