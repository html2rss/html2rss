# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('cli' => 'CLI')
loader.setup

require 'logger'
require 'forwardable'
require 'html2rss/configuration'

##
# The Html2rss namespace.
module Html2rss
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
    FeedPipeline.new(raw_config).to_rss
  end

  ##
  # Returns a JSONFeed 1.1 hash generated from the provided configuration.
  #
  # @param raw_config [Hash{Symbol => Object}] feed configuration
  # @return [Hash] JSONFeed-compliant hash
  def self.json_feed(raw_config)
    FeedPipeline.new(raw_config).to_json_feed
  end

  # rubocop:disable Metrics/ParameterLists

  ##
  # Scrapes the provided URL and returns an RSS object.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer, nil] optional request budget override
  # @param local_file_path [String, nil] optional local HTML file path
  # @return [RSS::Rss] generated RSS feed
  def self.auto_source(url,
                       strategy: :auto,
                       items_selector: nil,
                       max_redirects: nil,
                       max_requests: nil,
                       local_file_path: nil)
    feed(build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:, local_file_path:))
  end

  ##
  # Scrapes the provided URL and returns a JSONFeed 1.1 hash.
  #
  # @param url [String] source page URL
  # @param strategy [Symbol] request strategy to use
  # @param items_selector [String, nil] optional selector hint for item extraction
  # @param max_redirects [Integer, nil] optional redirect limit override
  # @param max_requests [Integer, nil] optional request budget override
  # @param local_file_path [String, nil] optional local HTML file path
  # @return [Hash] JSONFeed-compliant hash
  def self.auto_json_feed(url,
                          strategy: :auto,
                          items_selector: nil,
                          max_redirects: nil,
                          max_requests: nil,
                          local_file_path: nil)
    json_feed(build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:,
                                       local_file_path:))
  end

  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable ThreadSafety/ClassInstanceVariable
  class << self
    ##
    # @return [Html2rss::Configuration] the global configuration instance
    def configuration
      @configuration ||= Configuration.new.freeze
    end

    ##
    # Configures global library defaults.
    #
    # @yieldparam config [Html2rss::Configuration]
    # @return [Html2rss::Configuration] the frozen configuration
    def configure
      config = configuration.dup
      yield config
      @configuration = config.freeze
    end

    ##
    # @return [Object] the logger
    def logger
      configuration.logger
    end

    ##
    # @param logger [Object] the new logger
    def logger=(logger)
      configure { |config| config.logger = logger }
    end

    private

    ##
    # Resets the global configuration to defaults (mainly for testing).
    #
    # @return [void]
    def reset_configuration!
      @configuration = nil
      logger.level = configuration.log_level if logger.respond_to?(:level=)
    end
  end
  # rubocop:enable ThreadSafety/ClassInstanceVariable

  class << self
    private

    def build_auto_source_config(url:, strategy:, items_selector:, max_redirects:, max_requests:, local_file_path: nil) # rubocop:disable Metrics/ParameterLists
      config = Config.auto_source_config(
        url:,
        items_selector:,
        request_controls: shortcut_request_controls(strategy:, max_redirects:, max_requests:)
      )
      if local_file_path
        config[:request] ||= {}
        config[:request][:local_file_path] = local_file_path
      end
      config
    end

    def shortcut_request_controls(strategy:, max_redirects:, max_requests:)
      RequestControls.new(
        strategy:,
        max_redirects:,
        max_requests:,
        explicit_keys: explicit_request_control_keys(strategy:, max_redirects:, max_requests:)
      )
    end

    def explicit_request_control_keys(strategy:, max_redirects:, max_requests:)
      keys = []
      keys << :strategy unless strategy.nil? || strategy == Config.default_strategy_name
      keys << :max_redirects unless max_redirects.nil?
      keys << :max_requests unless max_requests.nil?
      keys
    end
  end

  logger.level = configuration.log_level if logger.respond_to?(:level=)
end

loader.eager_load
