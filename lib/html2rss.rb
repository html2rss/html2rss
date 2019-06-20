require 'html2rss/config'
require 'html2rss/feed_builder'
require 'html2rss/version'
require 'yaml'

module Html2rss
  def self.feed_from_yaml_config(file, name)
    yaml = YAML.load(File.open(file))
    feed_config = yaml['feeds'][name]
    global_config = yaml.reject { |k| k == 'feeds' }

    config = Config.new(feed_config, global_config)
    feed(config)
  end

  def self.feed(config)
    feed = FeedBuilder.new config
    feed.rss
  end
end
