module Html2rss
  class Config
    def initialize(feed_config, global_config = {})
      @global_config = Utils::IndifferentAccessHash.new global_config
      @feed_config = Utils::IndifferentAccessHash.new feed_config
      @channel_config = Utils::IndifferentAccessHash.new @feed_config.fetch('channel', {})
    end

    def author
      channel_config.fetch 'author', 'html2rss'
    end

    def ttl
      channel_config.fetch 'ttl', 3600
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

    def time_zone
      channel_config.fetch 'time_zone', 'UTC'
    end

    def json?
      channel_config.fetch 'json', false
    end

    def headers
      global_config.fetch('headers', {}).merge channel_config.fetch('headers', {})
    end

    def attribute_options(name)
      feed_config.dig('selectors').fetch(name, {}).merge('channel' => channel_config)
    end

    def attribute?(name)
      attribute_names.include?(name.to_s)
    end

    def categories
      feed_config.dig('selectors').fetch('categories', []).map(&:to_sym)
    end

    def selector(name)
      feed_config.dig('selectors', name, 'selector')
    end

    def attribute_names
      @attribute_names ||= feed_config.fetch('selectors', {}).keys.map(&:to_s).tap do |attrs|
        attrs.delete('items')
      end
    end

    private

    attr_reader :feed_config, :channel_config, :global_config
  end
end
