# frozen_string_literal: true

require 'zeitwerk'

loader = Zeitwerk::Loader.for_gem
loader.setup

require 'yaml'

##
# The Html2rss namespace.
module Html2rss
  CONFIG_KEY_FEEDS = :feeds

  ##
  # Returns a RSS object which is generated from the provided file.
  #
  # Example:
  #
  #    feed = Html2rss.feed_from_yaml_config(File.join(['spec', 'config.test.yml']), 'nuxt-releases')
  #    # => #<RSS::Rss:0x00007fb2f6331228
  #
  # @param file [File] a file object of the yaml file to use
  # @param name [String, Symbol, nil] name of the feed to generate from the yaml
  # @param global_config [Hash] global options (e.g. HTTP headers) to use
  # @param params [Hash] if required by feed config, the dynamic parameters for the config
  # @return [RSS::Rss]
  def self.feed_from_yaml_config(file, name = nil, global_config: {}, params: {})
    yaml = YAML.safe_load(File.open(file), symbolize_names: true)

    if name && (feeds = yaml[CONFIG_KEY_FEEDS])
      feed_config = feeds.fetch(name.to_sym)
      global_config.merge!(yaml.reject { |key| key == CONFIG_KEY_FEEDS })
    else
      feed_config = yaml
    end

    feed Config.new(feed_config, global_config, params)
  end

  ##
  # Returns a RSS object which is generated from the provided config.
  #
  # In case you need `global_config` or `params`, you need to
  # provide a Html2rss::Config instance as `config`.
  # Otherwise a Hash using Symbols as keys will do fine.
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
  # @param config [Hash<Symbol, Object>, Html2rss::Config]
  # @return [RSS::Rss]
  def self.feed(config)
    config = Config.new(config) unless config.is_a?(Config)

    RssBuilder.build config
  end
end
