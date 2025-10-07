# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('cli' => 'CLI')
loader.setup

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

  def self.config_from_yaml_file(file, feed_name = nil)
    Config.load_yaml(file, feed_name)
  end

  ##
  # Returns an RSS object generated from the provided configuration.
  #
  # Example:
  #
  #    feed = Html2rss.feed(
  #      strategy: :faraday,
  #      headers: { 'User-Agent' => 'Mozilla/5.0' },
  #      channel: { name: 'StackOverflow: Hot Network Questions', url: 'https://stackoverflow.com' },
  #      selectors: {
  #        items: { selector: '#hot-network-questions > ul > li' },
  #        title: { selector: 'a' },
  #        link: { selector: 'a', extractor: 'href' }
  #      },
  #      auto_source: {}
  #    )
  #    # => #<RSS::Rss:0x00007fb2f48d14a0 ...>
  #
  # @param config [Hash<Symbol, Object>] configuration.
  # @return [RSS::Rss] RSS object generated from the configuration.
  def self.feed(config)
    config = build_config(config)
    response = fetch_response(config)
    articles = collect_articles(response, config)

    channel = RssBuilder::Channel.new(response, overrides: config.channel)

    RssBuilder.new(channel:, articles:, stylesheets: config.stylesheets).call
  end

  def self.build_config(config)
    Config.from_hash(config, params: config[:params])
  end
  private_class_method :build_config

  def self.fetch_response(config)
    RequestService.execute(
      RequestService::Context.new(
        url: config.url,
        headers: config.headers,
        options: config.request_options
      ),
      strategy: config.strategy
    )
  end
  private_class_method :fetch_response

  def self.collect_articles(response, config)
    articles = []

    if (selectors = config.selectors)
      articles.concat Selectors.new(response, selectors:, time_zone: config.time_zone).articles
    end

    if (auto_source = config.auto_source)
      articles.concat AutoSource.new(response, auto_source).articles
    end

    ArticlePipeline.new(articles).call
  end
  private_class_method :collect_articles

  ##
  # Scrapes the provided URL and returns an RSS object.
  # No need for a "feed config".
  #
  # @param url [String] the URL to automatically source the feed from
  # @param strategy [Symbol] the request strategy to use
  # @param items_selector [String] CSS selector for items (will be enhanced) (optional)
  # @return [RSS::Rss]
  def self.auto_source(url, strategy: :faraday, items_selector: nil)
    config = Html2rss::Config.default_config.merge!(strategy:)
    config[:channel][:url] = url

    config[:auto_source] = Html2rss::AutoSource::DEFAULT_CONFIG
    config[:selectors] = { items: { selector: items_selector, enhance: true } } if items_selector

    feed(config)
  end
end

loader.eager_load
