# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'
require 'thor'

module Html2rss
  ##
  # The Html2rss command line interface.
  class CLI < Thor # rubocop:disable Metrics/ClassLength
    check_unknown_options!
    # Supported CLI strategy plan option values (:auto plus concrete strategies).
    #
    # @return [Array<String>]
    STRATEGY_OPTION_ENUM = Html2rss::FeedPipeline::StrategyPlan.accepted_names.map(&:to_s).freeze

    # User-facing strategy help text that reflects the current fallback chain.
    #
    # @return [String]
    STRATEGY_OPTION_DESC = [
      'Optional request strategy (defaults to auto; auto tries',
      "#{Html2rss::FeedPipeline::AutoFallback::CHAIN.join(' -> ')})"
    ].join(' ').freeze

    # @return [Boolean] whether Thor should terminate process on command failures
    def self.exit_on_failure?
      true
    end

    desc 'feed YAML_FILE [feed_name]', 'Print RSS built from the YAML_FILE file to stdout'
    method_option :params,
                  type: :hash,
                  optional: true,
                  required: false,
                  default: {}
    method_option :strategy,
                  type: :string,
                  desc: STRATEGY_OPTION_DESC,
                  enum: STRATEGY_OPTION_ENUM
    method_option :max_redirects,
                  type: :numeric,
                  desc: 'Maximum redirects to follow per request'
    method_option :max_requests,
                  type: :numeric,
                  desc: 'Maximum requests to allow for this feed build'
    method_option :input,
                  type: :string,
                  desc: 'Local HTML file path to read input from'
    # @param yaml_file [String] path to YAML config
    # @param feed_name [String, nil] optional named feed in multi-feed config
    # @return [void]
    def feed(yaml_file, feed_name = nil)
      config = Html2rss.config_from_yaml_file(yaml_file, feed_name)
      config[:params] = options[:params] || {}
      apply_runtime_request_overrides!(config)
      apply_local_file_input!(config, options[:input]) if options[:input]

      puts(execute_feed { Html2rss.feed(config) })
    end

    desc 'auto [URL]', 'Automatically sources an RSS feed from the URL'
    method_option :strategy,
                  type: :string,
                  desc: STRATEGY_OPTION_DESC,
                  enum: STRATEGY_OPTION_ENUM
    method_option :format,
                  type: :string,
                  desc: 'Output format for the auto-sourced feed',
                  enum: %w[rss jsonfeed],
                  default: 'rss'
    method_option :items_selector, type: :string, desc: 'CSS selector for items (will be enhanced) (optional)'
    method_option :max_redirects,
                  type: :numeric,
                  desc: 'Maximum redirects to follow per request'
    method_option :max_requests,
                  type: :numeric,
                  desc: 'Maximum requests to allow for this feed build'
    method_option :limit,
                  type: :numeric,
                  desc: 'Maximum number of articles to keep (default: 25)'
    method_option :input,
                  type: :string,
                  desc: 'Local HTML file path to read input from'
    method_option :explain,
                  type: :boolean,
                  desc: 'Print Status JSON to stderr (stdout stays the feed)',
                  default: false
    # @param url [String, nil] source page URL for auto discovery
    # @return [void]
    def auto(url = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- CLI option wiring
      format = options.fetch(:format, 'rss')
      strategy, local_file_path, url = prepare_auto_inputs(url, options[:input])
      feed_result = execute_feed { auto_feed_result_for(url, strategy, local_file_path) }

      explain_status!(feed_result.status) if options[:explain]
      puts(format == 'jsonfeed' ? JSON.pretty_generate(feed_result.to_json_feed) : feed_result.to_rss)
    end

    desc 'capture URL', 'Analyze a URL and print a reusable YAML feed config'
    method_option :strategy,
                  type: :string,
                  desc: STRATEGY_OPTION_DESC,
                  enum: STRATEGY_OPTION_ENUM
    method_option :items_selector, type: :string, desc: 'CSS selector hint for items (optional)'
    method_option :max_redirects,
                  type: :numeric,
                  desc: 'Maximum redirects to follow per request'
    method_option :max_requests,
                  type: :numeric,
                  desc: 'Maximum requests to allow for this feed build'
    method_option :limit,
                  type: :numeric,
                  desc: 'Maximum number of articles to keep (default: 25)'
    method_option :input,
                  type: :string,
                  desc: 'Local HTML file path to read input from'
    method_option :explain,
                  type: :boolean,
                  desc: 'Print capture quality JSON to stderr (stdout stays YAML)',
                  default: false
    ##
    # Captures a URL and prints a reusable YAML config.
    #
    # @param url [String, nil] source page URL for capture
    # @return [void]
    def capture(url = nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- CLI option wiring
      strategy, local_file_path, url = prepare_auto_inputs(url, options[:input])
      result = Html2rss::Capture.build(
        url,
        strategy:,
        items_selector: options[:items_selector],
        limit: options[:limit]&.to_i,
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests],
        local_file_path:
      )
      explain_capture!(result) if options[:explain]
      puts YAML.dump(HashUtil.deep_stringify_keys(result.config))
    end

    desc 'schema', 'Print the exported config JSON Schema'
    method_option :pretty,
                  type: :boolean,
                  desc: 'Pretty-print the schema JSON',
                  default: true
    method_option :write,
                  type: :string,
                  desc: 'Write the schema JSON to the given file path'
    ##
    # Prints or writes the exported configuration JSON Schema.
    #
    # @return [void]
    def schema
      schema_json = Html2rss::Config.json_schema_json(pretty: options.fetch(:pretty, true))

      if options[:write]
        FileUtils.mkdir_p(File.dirname(options[:write]))
        File.write(options[:write], "#{schema_json}\n")
        puts options[:write]
        return
      end

      puts schema_json
    end

    desc 'mcp', 'Start the MCP server for AI client consumption'
    method_option :transport,
                  type: :string,
                  desc: 'MCP transport protocol',
                  enum: %w[stdio http],
                  default: 'stdio'
    method_option :port,
                  type: :numeric,
                  desc: 'Port for HTTP transport (binds 127.0.0.1)',
                  default: 8080
    ##
    # Starts the MCP server for AI client consumption.
    #
    # @return [void]
    def mcp
      Html2rss::MCP.start(
        transport: options[:transport].to_sym,
        port: options[:port]
      )
    end

    desc 'validate YAML_FILE [feed_name]', 'Validate a YAML config with the runtime validator'
    method_option :params,
                  type: :hash,
                  optional: true,
                  required: false,
                  default: {}
    ##
    # Validates a YAML config and prints the result.
    #
    # @param yaml_file [String] the YAML file to validate
    # @param feed_name [String, nil] optional feed name for multi-feed files
    # @return [void]
    def validate(yaml_file, feed_name = nil)
      result = Html2rss::Config.validate_yaml(yaml_file, feed_name, params: options[:params] || {})

      raise Thor::Error, "Invalid configuration: #{result.errors.to_h}" unless result.success?

      puts 'Configuration is valid'
    end

    private

    def apply_runtime_request_overrides!(config)
      clear_blank_request_overrides!(config)
      request_controls.apply_to(config)
    end

    def clear_blank_request_overrides!(config)
      config.delete(:strategy) if config[:strategy].nil?

      request_config = config[:request]
      return unless request_config.is_a?(Hash)

      %i[max_redirects max_requests].each do |key|
        request_config.delete(key) if request_config[key].nil?
      end
      config.delete(:request) if request_config.empty?
    end

    def apply_local_file_input!(config, input_path)
      file_path = check_file_exists!(input_path)
      config[:strategy] = :local_file
      config[:request] = (config[:request] || {}).merge(local_file_path: file_path)

      return unless config.dig(:channel, :url).to_s.empty?

      config[:channel] = (config[:channel] || {}).merge(
        url: detect_base_url!(file_path, 'Please specify a channel.url in the config.')
      )
    end

    def prepare_auto_inputs(url, input_option)
      if input_option.nil?
        raise Thor::Error, 'A URL is required unless --input is specified' unless url

        return [current_strategy, nil, url]
      end

      file_path = check_file_exists!(input_option)
      detected_url = url || detect_base_url!(
        file_path, 'Please specify a URL: html2rss <command> [URL] --input <file>'
      )

      [:local_file, file_path, detected_url]
    end

    def request_controls
      Html2rss::Config::RequestControls.from_cli_options(
        strategy: options[:strategy],
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests]
      )
    end

    def current_strategy
      options[:strategy]&.to_sym || :auto
    end

    def current_max_redirects
      options.fetch(:max_redirects, Html2rss::RequestService::Policy::DEFAULTS[:max_redirects])
    end

    def current_max_requests
      options.fetch(:max_requests, Html2rss::RequestService::Policy::DEFAULTS[:max_requests])
    end

    def suggested_max_redirects
      current_max_redirects + 1
    end

    def suggested_max_requests
      current_max_requests + 1
    end

    def execute_feed # rubocop:disable Metrics/MethodLength
      yield
    rescue Faraday::FollowRedirects::RedirectLimitReached => error
      raise Thor::Error,
            "#{error.message}. already retried the last redirect hop once; " \
            "retry with --max-redirects #{suggested_max_redirects} or use the final URL directly."
    rescue Html2rss::RequestService::RequestBudgetExceeded => error
      raise Thor::Error,
            "#{error.message}. retry with --max-requests #{suggested_max_requests} " \
            'or increase request.max_requests in the config.'
    rescue Html2rss::RequestService::BotasaurusConfigurationError,
           Html2rss::RequestService::BotasaurusConnectionFailed,
           Html2rss::RequestService::BotasaurusServiceError,
           Html2rss::RequestService::BlockedSurfaceDetected,
           Html2rss::NoFeedItemsExtracted => error
      raise Thor::Error, error.message
    end

    def auto_feed_result_for(url, strategy, local_file_path)
      Html2rss.auto_feed_result(
        url,
        strategy:,
        items_selector: options[:items_selector],
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests],
        local_file_path:,
        limit: options[:limit]&.to_i
      )
    end

    def explain_status!(status)
      $stderr.puts JSON.pretty_generate(status.to_h) # rubocop:disable Style/StderrPuts -- CLI explain contract
    end

    def explain_capture!(result)
      $stderr.puts JSON.pretty_generate( # rubocop:disable Style/StderrPuts -- CLI explain contract
        articles_count: result.articles_count,
        channel_title: result.channel_title,
        has_selectors: !result.config[:selectors].nil? && !result.config[:selectors].empty?
      )
    end

    def check_file_exists!(path)
      File.expand_path(path).tap do |file_path|
        raise Thor::Error, "Input file does not exist: #{path}" unless File.exist?(file_path)
      end
    end

    def detect_base_url!(file_path, error_hint)
      Html2rss::Url.extract_from_html(File.read(file_path))&.to_s ||
        raise(Thor::Error, "Could not auto-detect a base URL from HTML metadata. #{error_hint}")
    end
  end
end
