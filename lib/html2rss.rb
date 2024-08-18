# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

require 'yaml'
require 'logger'

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
  # @return [RSS::Rss] RSS object generated from the configuration.
  def self.feed_from_yaml_config(file, name = nil, global_config: {}, params: {})
    yaml = load_yaml(file)
    feeds = yaml[CONFIG_KEY_FEEDS] || {}

    feed_config = find_feed_config(yaml, feeds, name, global_config)

    feed(Config.new(feed_config, global_config, params))
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
  # @param config [Hash<Symbol, Object>, Html2rss::Config] Feed configuration.
  # @return [RSS::Rss] RSS object generated from the configuration.
  def self.feed(config)
    config = Config.new(config) unless config.is_a?(Config)
    RssBuilder.build(config)
  end

  ##
  # Loads and parses the YAML file.
  #
  # @param file [String] Path to the YAML file.
  # @return [Hash] Parsed YAML content.
  def self.load_yaml(file)
    YAML.safe_load_file(file, symbolize_names: true)
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
    return yaml unless feed_name

    feed_name = feed_name.to_sym
    if feeds.key?(feed_name)
      global_config.merge!(yaml.reject { |key| key == CONFIG_KEY_FEEDS })
      feeds[feed_name]
    else
      yaml
    end
  end

  ##
  # Scrapes the provided URL and returns an RSS object.
  # No need for a "feed config".
  #
  # @return [RSS::Rss]
  def self.auto_source(url)
    url = Addressable::URI.parse(url)

    response = Html2rss::Utils.request_url(url)

    Html2rss::AutoSource.new(url, body: response.body, headers: response.headers).build
  end

  private_class_method :load_yaml, :find_feed_config
end
