# frozen_string_literal: true

require_relative '../html2rss'
require 'thor'

##
# The Html2rss namespace / command line interface.
module Html2rss
  Log = Logger.new($stderr)

  ##
  # The Html2rss command line interface.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc 'feed YAML_FILE [FEED_NAME] [param=value ...]', 'Print RSS built from the YAML_FILE file to stdout'
    ##
    # Prints the feed to STDOUT.
    #
    # @param yaml_file [String] Path to the YAML configuration file.
    # @param options [Array<String>] Additional options including feed name and parameters.
    # @return [nil]
    def feed(yaml_file, *options)
      raise "File '#{yaml_file}' does not exist" unless File.exist?(yaml_file)

      feed_name = options.shift unless options.first&.include?('=')
      params = options.to_h { |opt| opt.split('=', 2) }

      puts Html2rss.feed_from_yaml_config(yaml_file, feed_name, params:)
    end

    desc 'auto URL', 'Automatically sources an RSS feed from the URL'
    method_option :strategy,
                  type: :string,
                  desc: 'The strategy to request the URL',
                  enum: RequestService.strategy_names,
                  default: RequestService.default_strategy_name
    def auto(url)
      strategy = options.fetch(:strategy) { RequestService.default_strategy_name }.to_sym

      puts Html2rss.auto_source(url, strategy:)
    end
  end
end
