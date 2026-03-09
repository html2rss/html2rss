# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'thor'

##
# The Html2rss namespace / command line interface.
module Html2rss
  ##
  # The Html2rss command line interface.
  class CLI < Thor
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
    def feed(yaml_file, feed_name = nil)
      config = Html2rss.config_from_yaml_file(yaml_file, feed_name)
      config[:strategy] ||= options[:strategy]&.to_sym
      config[:params] = options[:params] || {}

      puts Html2rss.feed(config)
    end

    desc 'auto [URL]', 'Automatically sources an RSS feed from the URL'
    method_option :strategy,
                  type: :string,
                  desc: 'The strategy to request the URL',
                  enum: %w[faraday browserless],
                  default: 'faraday'
    method_option :items_selector, type: :string, desc: 'CSS selector for items (will be enhanced) (optional)'
    def auto(url)
      strategy = options.fetch(:strategy, 'faraday').to_sym

      puts Html2rss.auto_source(url, strategy:, items_selector: options[:items_selector])
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
  end
end
