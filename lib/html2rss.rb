# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

require 'addressable'
require 'logger'
require 'yaml'

##
# The Html2rss namespace.
module Html2rss
  ##
  # The logger instance.
  Log = Logger.new($stdout)

  Log.level = ENV.fetch('LOG_LEVEL', :warn).upcase.to_sym

  Log.formatter = proc do |severity, datetime, _progname, msg|
    "#{datetime} [#{severity}] #{msg}\n"
  end

  ##
  # The Html2rss::Error base class.
  class Error < StandardError; end

  ##
  # Key for the feeds configuration in the YAML file.
  CONFIG_KEY_FEEDS = :feeds

  ##
  # Returns an RSS object generated from the provided YAML file configuration.
  #
  # Example:
  #
  #    feed = Html2rss.feed_from_yaml_config(File.join(['spec', 'config.test.yml']), 'nuxt-releases')
  #    # => #<RSS::Rss:0x00007fb2f6331228
  #
  # @param file [String] Path to the YAML file.
  # @param name [String, Symbol, nil] Name of the feed in the YAML file.
  # @param global_config [Hash] Global options (e.g., HTTP headers).
  # @param params [Hash] Dynamic parameters for the feed configuration.
  # @return [Hash<Symbol, Object>] Feed configuration.
  def self.config_from_yaml_config(file, name = nil, global_config: {}, params: {})
    raise "File '#{file}' does not exist" unless File.exist?(file)

    yaml = YAML.safe_load_file(file, symbolize_names: true)
    feeds = yaml[CONFIG_KEY_FEEDS] || {}

    feed_config = find_feed_config(yaml, feeds, name, global_config)

    stylesheets = yaml[:stylesheets].to_a.map { |style| Html2rss::RssBuilder::Stylesheet.new(**style) }

    {
      channel: feed_config[:channel],
      selectors: feed_config[:selectors],
      stylesheets:, global_config:, params:
    }
  end

  ##
  # Returns an RSS object generated from the provided configuration.
  #
  # Example:
  #
  #    feed = Html2rss.feed(
  #      channel: { name: 'StackOverflow: Hot Network Questions', url: 'https://stackoverflow.com' },
  #      selectors: {
  #        items: { selector: '#hot-network-questions > ul > li' },
  #        title: { selector: 'a' },
  #        link: { selector: 'a', extractor: 'href' }
  #      }
  #    )
  #    # => #<RSS::Rss:0x00007fb2f48d14a0 ...>
  #
  # @param config [Hash<Symbol, Object>] configuration.
  # @return [RSS::Rss] RSS object generated from the configuration.
  def self.feed(config)
    headers = config.dig(:channel, :headers)
    strategy = config.dig(:channel, :strategy) || RequestService.default_strategy_name
    stylesheets = config[:stylesheets] || []
    params = config[:params]

    channel = config[:channel]
    selectors = config[:selectors]

    # global_config = config[:global_config] # TODO: get rid of this crutch in favor of proper "gem configuration"

    channel = channel.transform_values { |value| value.is_a?(String) ? format(value, params) : value }
    url = Addressable::URI.parse(channel[:url])

    response = RequestService.execute(RequestService::Context.new(url:, headers:), strategy:)

    Scrapers::Selectors.call(url, body: response.body, headers: response.headers,
                                  selectors:, channel:, stylesheets:, params:)
  end

  ##
  # Builds the feed configuration based on the provided parameters.
  #
  # @param yaml [Hash] Parsed YAML content.
  # @param feeds [Hash] Feeds from the YAML content.
  # @param feed_name [String, Symbol, nil] Name of the feed in the YAML file.
  # @param global_config [Hash] Global options (e.g., HTTP headers).
  # @return [Hash] Feed configuration.
  def self.find_feed_config(yaml, feeds, feed_name, global_config)
    global_config.merge!(yaml.reject { |key| key == CONFIG_KEY_FEEDS })

    config = if !yaml.key?(CONFIG_KEY_FEEDS)
               yaml
             elsif feed_name
               feeds[feed_name.to_sym]
             end

    raise "Feed '#{feed_name}' not found in the configuration" unless config

    config.merge(global_config)
  end

  ##
  # Scrapes the provided URL and returns an RSS object.
  # No need for a "feed config".
  #
  # @param url [String] the URL to automatically source the feed from
  # @param strategy [Symbol] the request strategy to use
  # @return [RSS::Rss]
  def self.auto_source(url, strategy: :faraday)
    ctx = RequestService::Context.new(url:, headers: {})
    response = RequestService.execute(ctx, strategy:)

    Html2rss::AutoSource.new(ctx.url, body: response.body, headers: response.headers).build
  end

  private_class_method :find_feed_config
end
