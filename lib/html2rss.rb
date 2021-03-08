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
  # @param name [String, nil] name of the feed to generate from the yaml
  # @param global_config [Hash] global options (e.g. HTTP headers) to use
  # @param params [Hash] if required by feed config, the dynamic parameters for the config
  # @return [RSS::Rss]
  def self.feed_from_yaml_config(file, name = nil, global_config: {}, params: {})
    feed_config = YAML.safe_load(File.open(file))

    if name && (feed_config = feed_config.dig('feeds', name))
      global_config.merge!(feed_config.reject { |key| key == 'feeds' })
    end

    feed Config.new(feed_config, global_config, params)
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
  # @param config [Html2rss::Config]
  # @return [RSS::Rss]
  def self.feed(config)
    raise 'given config must be a Html2rss::Config instance' unless config.is_a?(Config)

    feed = FeedBuilder.new config
    feed.rss
  end
end
