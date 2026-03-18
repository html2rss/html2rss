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

  ##
  # Loads a feed configuration from YAML.
  #
  # @param file [String] path to the YAML file
  # @param feed_name [String, nil] optional feed name inside a multi-feed config
  # @return [Hash<Symbol, Object>] loaded configuration hash
  def self.config_from_yaml_file(file, feed_name = nil)
    Config.load_yaml(file, feed_name)
  end

  ##
  # Returns an RSS object generated from the provided configuration.
  #
  # @param raw_config [Hash<Symbol, Object>] feed configuration
  # @return [RSS::Rss] generated RSS feed
  def self.feed(raw_config)
    run_pipeline(raw_config) do |response:, config:, articles:|
      build_rss_feed(response:, config:, articles:)
    end
  end

  ##
  # Returns a JSONFeed 1.1 hash generated from the provided configuration.
  #
  # @param raw_config [Hash<Symbol, Object>] feed configuration
  # @return [Hash] JSONFeed-compliant hash
  def self.json_feed(raw_config)
    run_pipeline(raw_config) do |response:, config:, articles:|
      build_json_feed(response:, config:, articles:)
    end
  end

  ##
  # Scrapes the provided URL and returns an RSS object.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer, nil] optional request budget override
  # @return [RSS::Rss] generated RSS feed
  def self.auto_source(url, strategy: :faraday, items_selector: nil, max_redirects: nil, max_requests: nil)
    feed(build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:))
  end

  ##
  # Scrapes the provided URL and returns a JSONFeed 1.1 hash.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer, nil] optional request budget override
  # @return [Hash] JSONFeed-compliant hash
  def self.auto_json_feed(url, strategy: :faraday, items_selector: nil, max_redirects: nil, max_requests: nil)
    json_feed(build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:))
  end

  class << self
    private

    def run_pipeline(raw_config)
      # 1. Normalize and validate the user-facing feed config.
      config = Config.from_hash(raw_config, params: raw_config[:params])

      # 2. Fetch the initial page using a shared request session.
      request_session = RequestSession.for_config(config)
      response = request_session.fetch_initial_response

      # 3. Collect articles from configured selectors and auto-source scrapers.
      articles = Articles::Deduplicator.new(
        collect_articles(response:, config:, request_session:)
      ).call

      # 4. Render the final output format chosen by the public entrypoint.
      yield response:, config:, articles:
    end

    def collect_articles(response:, config:, request_session:)
      selector_articles(response:, config:, request_session:) +
        auto_source_articles(response:, config:, request_session:)
    end

    def selector_articles(response:, config:, request_session:) # rubocop:disable Metrics/MethodLength
      return [] unless (selectors = config.selectors)

      page_responses = if (max_pages = selectors.dig(:items, :pagination, :max_pages))
                         RequestSession::RelNextPager.new(
                           session: request_session,
                           initial_response: response,
                           max_pages:
                         ).to_a
                       else
                         [response]
                       end

      page_responses.flat_map do |page_response|
        Selectors.new(page_response, selectors:, time_zone: config.time_zone).articles
      end
    end

    def auto_source_articles(response:, config:, request_session:)
      return [] unless (auto_source = config.auto_source)

      AutoSource.new(response, auto_source, request_session:).articles
    end

    def build_rss_feed(response:, config:, articles:)
      channel = RssBuilder::Channel.new(response, overrides: config.channel)

      RssBuilder.new(channel:, articles:, stylesheets: config.stylesheets).call
    end

    def build_json_feed(response:, config:, articles:)
      channel = RssBuilder::Channel.new(response, overrides: config.channel)

      JsonFeedBuilder.new(channel:, articles:).call
    end

    def explicit_request_control_keys(strategy:, max_redirects:, max_requests:)
      keys = []
      keys << :strategy unless strategy == :faraday
      keys << :max_redirects unless max_redirects.nil?
      keys << :max_requests unless max_requests.nil?
      keys
    end

    def build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:)
      Config.auto_source_config(
        url:,
        items_selector:,
        request_controls: shortcut_request_controls(strategy:, max_redirects:, max_requests:)
      )
    end

    def shortcut_request_controls(strategy:, max_redirects:, max_requests:)
      RequestControls.new(
        strategy:,
        max_redirects:,
        max_requests:,
        explicit_keys: explicit_request_control_keys(strategy:, max_redirects:, max_requests:)
      )
    end
  end
end

loader.eager_load
