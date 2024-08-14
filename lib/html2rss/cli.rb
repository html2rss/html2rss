# frozen_string_literal: true

require_relative '../html2rss'
require 'thor'
require 'addressable'

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

      feed_name = options.shift
      params = options.to_h { |opt| opt.split('=', 2) }
      puts Html2rss.feed_from_yaml_config(yaml_file, feed_name, params:)
    end

    desc 'auto URL', 'automatically sources an RSS feed from the URL'
    def auto(url)
      url = url.to_s.strip

      raise 'An absolute URL is required' if url.empty? || !Addressable::URI.parse(url).absolute?

      puts Html2rss.auto_source(url)
    end
  end
end
