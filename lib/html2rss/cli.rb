# frozen_string_literal: true

require 'html2rss'
require 'thor'

##
# The Html2rss command line
module Html2rss
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc 'feed FEED_CONFIG', 'print RSS built from the FEED_CONFIG file to stdout'
    def feed(feed_config)
      raise 'feed_config file does not exist' unless File.exist?(feed_config)

      parsed_feed_config = YAML.safe_load(File.read(feed_config))
      config = Config.new(parsed_feed_config)

      puts Html2rss.feed(config)
    end
  end
end
