# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('cli' => 'CLI')
loader.setup

require 'logger'

##
# The Html2rss namespace.
module Html2rss # rubocop:disable Metrics/ModuleLength
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
  # @return [Hash{Symbol => Object}] loaded configuration hash
  def self.config_from_yaml_file(file, feed_name = nil)
    Config.load_yaml(file, feed_name)
  end

  ##
  # Returns an RSS object generated from the provided configuration.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @return [RSS::Rss] generated RSS feed
  def self.feed(raw_config)
    run_pipeline(raw_config) do |response:, config:, articles:|
      build_rss_feed(response:, config:, articles:)
    end
  end

  ##
  # Returns a JSONFeed 1.1 hash generated from the provided configuration.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
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
  def self.auto_source(url, strategy: :auto, items_selector: nil, max_redirects: nil, max_requests: nil)
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
  def self.auto_json_feed(url, strategy: :auto, items_selector: nil, max_redirects: nil, max_requests: nil)
    json_feed(build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:))
  end

  class << self # rubocop:disable Metrics/ClassLength
    private

    def run_pipeline(raw_config)
      config = Config.from_hash(raw_config, params: raw_config[:params])
      pipeline_state = pipeline_state_for(config)

      yield response: pipeline_state.fetch(:response), config:, articles: pipeline_state.fetch(:articles)
    end

    def pipeline_state_for(config)
      return run_pipeline_for_strategy(config, strategy: config.strategy) unless config.strategy == :auto

      run_auto_pipeline(config)
    end

    def run_pipeline_for_strategy(config, strategy:, budget: nil)
      request_session = request_session_for(config, strategy:, budget:)
      response = request_session.fetch_initial_response
      articles = Articles::Deduplicator.new(
        collect_articles(response:, config:, request_session:)
      ).call

      { response:, articles: }
    end

    def run_auto_pipeline(config) # rubocop:disable Metrics/MethodLength
      attempts = []
      last_error = nil
      shared_budget = auto_pipeline_budget(config)

      concrete_auto_strategies.each do |strategy|
        state, attempts, last_error = execute_auto_attempt(
          config:,
          strategy:,
          attempts:,
          last_error:,
          budget: shared_budget
        )
        return state if state
      end

      raise NoFeedItemsExtracted.new(attempts:) if auto_pipeline_zero_items_terminal?(attempts)
      raise last_error if last_error

      raise NoFeedItemsExtracted.new(attempts:)
    end

    def execute_auto_attempt(config:, strategy:, attempts:, last_error:, budget:) # rubocop:disable Metrics/MethodLength
      request_session = request_session_for(config, strategy:, budget:)
      response, attempts, last_error = fetch_auto_response(
        request_session:,
        strategy:,
        attempts:,
        last_error:
      )
      return [nil, attempts, last_error] unless response

      articles = auto_attempt_articles(response:, config:, request_session:)
      items_count = articles.size
      attempts << { strategy:, items_count:, error_class: nil }
      Log.debug("#{self}: auto pipeline strategy=#{strategy} items=#{items_count}")

      return [{ response:, articles: }, attempts, last_error] if items_count.positive?

      [nil, attempts, last_error]
    end

    def request_session_for(config, strategy:, budget: nil)
      RequestSession.from_runtime_input(runtime_input_for(config, strategy:), budget:)
    end

    def runtime_input_for(config, strategy:)
      RequestSession::RuntimeInput.new(
        url: config.url,
        headers: config.headers,
        request: config.request,
        strategy:,
        request_policy: RequestSession::RuntimePolicy.from_config(config)
      )
    end

    def auto_pipeline_budget(config)
      policy = RequestSession::RuntimePolicy.from_config(config)
      RequestService::Budget.new(max_requests: policy.max_requests)
    end

    def concrete_auto_strategies
      RequestService::AutoStrategy::CHAIN
    end

    def auto_pipeline_zero_items_terminal?(attempts)
      successful_counts = attempts.filter_map { _1[:items_count] }
      successful_counts.any? && successful_counts.all?(&:zero?)
    end

    def fetch_auto_response(request_session:, strategy:, attempts:, last_error:)
      [request_session.fetch_initial_response, attempts, last_error]
    rescue *RequestService::AutoStrategy::NON_FALLBACK_ERRORS
      raise
    rescue StandardError => error
      attempts << { strategy:, items_count: nil, error_class: error.class.name }
      Log.debug("#{self}: auto pipeline strategy=#{strategy} error=#{error.class}: #{error.message}")
      [nil, attempts, error]
    end

    def auto_attempt_articles(response:, config:, request_session:)
      Articles::Deduplicator.new(
        collect_articles(response:, config:, request_session:)
      ).call
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
      keys << :strategy unless strategy.nil? || strategy == RequestService.default_strategy_name
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
