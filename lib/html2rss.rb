require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

require 'yaml'

##
# The Html2rss namespace.
# Request HTML from an URL and transform it to a RSS 2.0 object.
module Html2rss
  ##
  # Returns a RSS object which is generated from the provided file.
  #
  # `file_path`: a File object of a YAML file
  # `name`: the of the feed
  #
  # Example:
  #
  #    feed = Html2rss.feed_from_yaml_config(File.join(['spec', 'config.test.yml']), 'nuxt-releases')
  #    # => #<RSS::Rss:0x00007fb2f6331228
  # @return [RSS:Rss]
  def self.feed_from_yaml_config(file, name)
    yaml = YAML.safe_load(File.read(file), aliases: true)

    feed_config = yaml['feeds'][name]
    global_config = yaml.reject { |key| key == 'feeds' }

    config = Config.new(feed_config, global_config)
    feed(config)
  end

  ##
  # Returns a RSS object which is generated from the provided config.
  #
  # `config`: can be a Hash or an instance of Html2rss::Config.
  #
  # Example:
  #
  #    feed = Html2rss.feed(
  #      channel: { name: 'StackOverflow: Hot Network Questions', url: 'https://stackoverflow.com' },
  #      selectors: {
  #        items: { selector: '#hot-network-questions > ul > li' },
  #        title: { selector: 'a' },
  #        link: { selector: 'a', extractor: 'href' }
  #      }
  #    )
  #    # => #<RSS::Rss:0x00007fb2f48d14a0 ...>
  # @return [RSS:Rss]
  def self.feed(config)
    config = Config.new(config) unless config.is_a?(Config)

    feed = FeedBuilder.new config
    feed.rss
  end
end
