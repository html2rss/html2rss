require 'html2rss/config'
require 'html2rss/feed_builder'
require 'html2rss/version'
require 'yaml'

module Html2rss
  def self.feed_from_yaml_config(file, name)
    config = Config.new(YAML.load(File.open(file))['feeds'].freeze, name)
    feed(config)
  end

  def self.feed(config)
    feed = FeedBuilder.new config
    feed.rss
  end
end
