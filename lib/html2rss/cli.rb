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

    desc 'feed YAML_FILE [FEED_NAME]', 'print RSS built from the FEED_CONFIG file to stdout'
    def feed(yaml_file, feed_name = nil)
      raise 'yaml_file file does not exist' unless File.exist?(yaml_file)

      puts Html2rss.feed_from_yaml_config(yaml_file, feed_name)
    end
  end
end
