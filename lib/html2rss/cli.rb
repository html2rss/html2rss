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

    desc 'feed YAML_FILE [FEED_NAME] [param=value ...]', 'print RSS built from the FEED_CONFIG file to stdout'
    def feed(yaml_file, *options)
      raise 'yaml_file file does not exist' unless File.exist?(yaml_file)

      params = options.map { |param| param.split('=') if param.include?('=') }.compact.to_h
      feed_name = options.first
      puts Html2rss.feed_from_yaml_config(yaml_file, feed_name, params: params)
    end
  end
end
