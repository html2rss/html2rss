require 'html2rss/config'
require 'html2rss/feed_builder'
require 'html2rss/version'
require 'yaml'

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
  def self.feed_from_yaml_config(file, name)
    # rubocop:disable Security/YAMLLoad
    yaml = YAML.load(File.open(file))
    # rubocop:enable Security/YAMLLoad

    feed_config = yaml['feeds'][name]
    global_config = yaml.reject { |k| k == 'feeds' }

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
  def self.feed(config)
    config = Config.new(config) unless config.is_a?(Config)

    feed = FeedBuilder.new config
    feed.rss
  end
end
