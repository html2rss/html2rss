# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'thor'

##
# The Html2rss namespace / command line interface.
module Html2rss
  ##
  # The Html2rss command line interface.
  class CLI < Thor # rubocop:disable Metrics/ClassLength
    check_unknown_options!

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
                  desc: 'The strategy to request the URL',
                  enum: %w[faraday browserless],
                  default: 'faraday'
    method_option :max_redirects,
                  type: :numeric,
                  desc: 'Maximum redirects to follow per request',
                  default: Html2rss::RequestService::Policy::DEFAULTS[:max_redirects]
    method_option :max_requests,
                  type: :numeric,
                  desc: 'Maximum requests to allow for this feed build',
                  default: Html2rss::RequestService::Policy::DEFAULTS[:max_requests]
    def feed(yaml_file, feed_name = nil)
      config = Html2rss.config_from_yaml_file(yaml_file, feed_name)
      config[:params] = options[:params] || {}
      config.merge!(
        strategy: options.fetch(:strategy, 'faraday').to_sym,
        max_redirects: options[:max_redirects],
        max_requests: options[:max_requests]
      ) { |_key, current, _default| current }

      puts(execute_feed { Html2rss.feed(config) })
    end

    desc 'auto [URL]', 'Automatically sources an RSS feed from the URL'
    method_option :strategy,
                  type: :string,
                  desc: 'The strategy to request the URL',
                  enum: %w[faraday browserless],
                  default: 'faraday'
    method_option :format,
                  type: :string,
                  desc: 'Output format for the auto-sourced feed',
                  enum: %w[rss jsonfeed],
                  default: 'rss'
    method_option :items_selector, type: :string, desc: 'CSS selector for items (will be enhanced) (optional)'
    method_option :max_redirects,
                  type: :numeric,
                  desc: 'Maximum redirects to follow per request',
                  default: Html2rss::RequestService::Policy::DEFAULTS[:max_redirects]
    method_option :max_requests,
                  type: :numeric,
                  desc: 'Maximum requests to allow for this feed build',
                  default: Html2rss::RequestService::Policy::DEFAULTS[:max_requests]
    def auto(url) # rubocop:disable Metrics/MethodLength
      source_method =
        options.fetch(:format, 'rss') == 'jsonfeed' ? Html2rss.method(:auto_json_feed) : Html2rss.method(:auto_source)

      puts(
        execute_feed do
          source_method.call(
            url,
            strategy: options.fetch(:strategy, 'faraday').to_sym,
            items_selector: options[:items_selector],
            max_redirects: options[:max_redirects],
            max_requests: options[:max_requests]
          )
        end
      )
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

    def execute_feed
      yield
    rescue Faraday::FollowRedirects::RedirectLimitReached => error
      raise Thor::Error, "#{error.message}. retry with --max-redirects 10 or use the final URL directly."
    rescue Html2rss::RequestService::RequestBudgetExceeded => error
      raise Thor::Error,
            "#{error.message}. retry with --max-requests 5 or increase top-level max_requests in the config."
    end
  end
end
