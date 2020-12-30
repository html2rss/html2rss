# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

require 'yaml'

##
# The Html2rss namespace.
module Html2rss
  ##
  # Returns a RSS object which is generated from the provided file.
  #
  # Example:
  #
  #    feed = Html2rss.feed_from_yaml_config(File.join(['spec', 'config.test.yml']), 'nuxt-releases')
  #    # => #<RSS::Rss:0x00007fb2f6331228
  #
  # @param file [File] a file object of the yaml file to use
  # @param name [String] name of the feed to generate from the yaml
  # @return [RSS::Rss]
  def self.feed_from_yaml_config(file, name)
    # rubocop:disable Security/YAMLLoad
    yaml = YAML.load(File.open(file))
    # rubocop:enable Security/YAMLLoad

    feed_config = yaml['feeds'][name]
    global_config = yaml.reject { |key| key == 'feeds' }

    config = Config.new(feed_config, global_config)
    feed(config)
  end

  ##
  # Returns a RSS object which is generated from the provided config.
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
  #
  # @param config [Html2rss::Config, Hash<String, Object>]
  # @return [RSS::Rss]
  def self.feed(config)
    config = Config.new(config) unless config.is_a?(Config)

    feed = FeedBuilder.new config
    feed.rss
  end
end
