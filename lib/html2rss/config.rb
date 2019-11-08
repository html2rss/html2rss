module Html2rss
  ##
  # The Config class abstracts from the config data structure and
  # provides default values.
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
      channel_config.fetch 'ttl', 360
    end

    def title
      channel_config.fetch 'title' do
        uri = URI(url)

        nicer_path = uri.path.split('/')
        nicer_path.compact!
        nicer_path.map!(&:titleize)

        "#{uri.host}: #{nicer_path.join(' ')}".squish
      end
    end

    def language
      channel_config.fetch 'language', 'en'
    end

    def description
      channel_config.fetch 'description', "Latest items from #{url}."
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
      global_config.fetch('headers', {}).merge(channel_config.fetch('headers', {}))
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
