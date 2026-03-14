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
  # @param raw_config [Hash<Symbol, Object>] configuration.
  # @return [RSS::Rss] RSS object generated from the configuration.
  def self.feed(raw_config)
    build_pipeline(raw_config) { |response, config, articles| build_rss_feed(response, config, articles) }
  end

  ##
  # Returns a JSONFeed 1.1 hash generated from the provided configuration.
  #
  # @param raw_config [Hash<Symbol, Object>] configuration.
  # @return [Hash] JSONFeed-compliant hash.
  # @see https://www.jsonfeed.org/version/1.1/
  def self.json_feed(raw_config)
    build_pipeline(raw_config) { |response, config, articles| build_json_feed(response, config, articles) }
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
    feed(auto_source_config(url, strategy:, items_selector:))
  end

  ##
  # Scrapes the provided URL and returns a JSONFeed 1.1 hash.
  # No need for a "feed config".
  #
  # @param url [String] the URL to automatically source the feed from
  # @param strategy [Symbol] the request strategy to use
  # @param items_selector [String] CSS selector for items (will be enhanced) (optional)
  # @return [Hash] JSONFeed-compliant hash.
  def self.auto_json_feed(url, strategy: :faraday, items_selector: nil)
    json_feed(auto_source_config(url, strategy:, items_selector:))
  end

  class << self
    private

    def build_pipeline(raw_config)
      config = Config.from_hash(raw_config, params: raw_config[:params])
      request_session = request_session_for(config)
      response = request_session.fetch_initial_response
      articles = collect_articles(response, config, request_session)
      processed_articles = Articles::Deduplicator.new(articles).call

      yield response, config, processed_articles
    end

    def auto_source_config(url, strategy:, items_selector:)
      Html2rss::Config.default_config.merge!(strategy:).tap do |config|
        config[:channel][:url] = url
        config[:auto_source] = Html2rss::AutoSource::DEFAULT_CONFIG
        config[:selectors] = { items: { selector: items_selector, enhance: true } } if items_selector
      end
    end

    def request_session_for(config)
      RequestSession.new(
        context: RequestService::Context.new(
          url: config.url,
          headers: config.headers,
          policy: RequestService::Policy.new(max_requests: requested_pages_for(config))
        ),
        strategy: config.strategy
      )
    end

    def requested_pages_for(config)
      config.selectors&.dig(:items, :pagination, :max_pages) || 1
    end

    def collect_articles(response, config, request_session)
      selector_articles(response, config, request_session) +
        auto_source_articles(response, config)
    end

    def selector_articles(response, config, request_session)
      return [] unless (selectors = config.selectors)

      selector_responses(response, selectors, request_session).flat_map do |page_response|
        Selectors.new(page_response, selectors:, time_zone: config.time_zone).articles
      end
    end

    def selector_responses(initial_response, selectors, request_session)
      max_pages = selectors.dig(:items, :pagination, :max_pages) || 1
      return [initial_response] if max_pages == 1

      RequestSession::RelNextPager.new(
        session: request_session,
        initial_response:,
        max_pages:
      ).to_a
    end

    def auto_source_articles(response, config)
      return [] unless (auto_source = config.auto_source)

      AutoSource.new(response, auto_source).articles
    end

    def build_rss_feed(response, config, articles)
      channel = RssBuilder::Channel.new(response, overrides: config.channel)

      RssBuilder.new(channel:, articles:, stylesheets: config.stylesheets).call
    end

    def build_json_feed(response, config, articles)
      channel = RssBuilder::Channel.new(response, overrides: config.channel)

      JsonFeedBuilder.new(channel:, articles:).call
    end
  end
end

loader.eager_load
