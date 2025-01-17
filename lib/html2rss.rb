# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

require 'addressable'
require 'logger'
require 'nokogiri'
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
  # Returns the feed configuration from the YAML file.
  #
  # It supports multiple feeds under the feeds: key and a single feed configurations.
  #
  # @param file [String] the YAML file.
  # @param feed_name [String] the feed name (only when feeds: is present).
  # @return [Hash<Symbol, Object>] the configuration.
  def self.config_from_yaml_file(file, feed_name = nil)
    raise "File '#{file}' does not exist" unless File.exist?(file)

    yaml = YAML.safe_load_file(file, symbolize_names: true)

    return yaml unless yaml.key?(CONFIG_KEY_FEEDS)

    if (config = yaml[CONFIG_KEY_FEEDS][feed_name.to_sym])
      return config.merge(stylesheets: yaml[:stylesheets], params: yaml[:params], strategy: yaml[:strategy])
    end

    raise("Feed '#{feed_name}' not found in the yaml file. Available names: #{yaml[CONFIG_KEY_FEEDS].keys.join(', ')}")
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
  def self.feed(config) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    # Step 1: Process the config

    strategy = config[:strategy] || config.dig(:channel, :strategy) || RequestService.default_strategy_name
    headers = config[:headers] || config.dig(:channel, :headers)

    channel = DynamicParams.call(config[:channel], config[:params])
    url = Addressable::URI.parse(channel[:url])
    time_zone = channel[:time_zone] || 'UTC'

    # Step 2: Execute the request and get the response
    response = RequestService.execute(RequestService::Context.new(url:, headers:), strategy:)

    # Step 3: Feed the scrapers with response, their settings, and get the articles
    articles = []

    if (selectors = config[:selectors])
      articles.concat Selectors.new(response, selectors:, time_zone:).articles
    end

    articles.concat Html2rss::AutoSource.new(response).articles if config[:auto_source].is_a?(Hash)

    # Step 4: combine / reduce all the extracted articles to prevent duplicates
    articles = AutoSource::Reducer.call(articles, url:)

    # Step 5: Build the RSS feed
    channel = RssBuilder::Channel.new(response, overrides: channel)
    stylesheets = (config[:stylesheets] || []).map { |style| Html2rss::RssBuilder::Stylesheet.new(**style) }

    RssBuilder.new(channel:, articles:, stylesheets:).call
  end

  ##
  # Scrapes the provided URL and returns an RSS object.
  # No need for a "feed config".
  #
  # @param url [String] the URL to automatically source the feed from
  # @param strategy [Symbol] the request strategy to use
  # @return [RSS::Rss]
  def self.auto_source(url, strategy: :faraday)
    Html2rss.feed(
      strategy:,
      channel: { url: url },
      auto_source: {}
    )
  end
end
