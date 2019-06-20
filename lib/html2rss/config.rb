module Html2rss
  class Config
    attr_reader :feed_config, :channel_config, :global_config

    def initialize(feed_config, global_config = {})
      @global_config = global_config
      @feed_config = feed_config
      @channel_config = feed_config.fetch('channel', {})
    end

    def author
      channel_config.fetch 'author', 'html2rss'
    end

    def ttl
      (channel_config.fetch 'ttl').to_i || nil
    end

    def title
      channel_config.fetch 'title', 'html2rss generated title'
    end

    def language
      channel_config.fetch 'language', 'en'
    end

    def description
      channel_config.fetch 'description', 'A description of my html2rss feed.'
    end

    def url
      channel_config.dig 'url'
    end
    alias link url

    def headers
      global_config.fetch('headers', {})
    end

    def options(name)
      feed_config.dig('selectors').fetch(name, {}).merge('channel' => channel_config)
    end

    def categories
      feed_config.dig('selectors').fetch('categories', [])
    end

    def selector(name)
      feed_config.dig('selectors', name, 'selector')
    end

    def attribute_names
      attribute_names = feed_config.fetch('selectors', {}).keys.map(&:to_s)
      attribute_names.delete('items')
      attribute_names
    end
  end
end
