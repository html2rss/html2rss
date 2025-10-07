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
    # 1. Normalize the configuration so collaborators receive validated input.
    config = Config.from_hash(config, params: config[:params])

    # 2. Perform the HTTP request with the configured strategy and options.
    response = RequestService.execute(
      RequestService::Context.new(
        url: config.url,
        headers: config.headers,
        options: config.request_options
      ),
      strategy: config.strategy
    )

    # 3. Extract articles using selectors and optional auto-source discovery.
    articles = []

    if (selectors = config.selectors)
      selector_service = Selectors.new(response, selectors:, time_zone: config.time_zone)
      articles.concat(selector_service.articles)
    end

    if (auto_source = config.auto_source)
      auto_source_service = AutoSource.new(response, auto_source)
      articles.concat(auto_source_service.articles)
    end

    # 4. Run the collected articles through the article pipeline for processing.
    processed_articles = ArticlePipeline.new(articles).call

    # 5. Build the RSS channel and final feed output.
    channel = RssBuilder::Channel.new(response, overrides: config.channel)

    RssBuilder.new(channel:, articles: processed_articles, stylesheets: config.stylesheets).call
  end

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
