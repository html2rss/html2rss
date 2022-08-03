# frozen_string_literal: true

require_relative '../html2rss'
require 'thor'

module Html2rss
  ##
  # The Html2rss command line
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc 'feed YAML_FILE [FEED_NAME] [param=value ...]', 'print RSS built from the YAML_FILE file to stdout'
    ##
    # Prints the feed to STDOUT.
    #
    # @param yaml_file [String]
    # @param options [String]
    # @return nil
    def feed(yaml_file, *options)
      raise 'yaml_file file does not exist' unless File.exist?(yaml_file)

      params = options.filter_map { |param| param.split('=') if param.include?('=') }.to_h
      feed_name = options.first
      puts Html2rss.feed_from_yaml_config(yaml_file, feed_name, params:)
    end
  end
end
