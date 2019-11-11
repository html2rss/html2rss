require 'active_support/core_ext/hash'

module Html2rss
  ##
  # The Config class abstracts from the config data structure and
  # provides default values.
  class Config
    def initialize(feed_config, global_config = {})
      @global_config = global_config.deep_symbolize_keys
      @feed_config = feed_config.deep_symbolize_keys
      @channel_config = @feed_config.fetch(:channel, {})
    end

    def author
      channel_config.fetch :author, 'html2rss'
    end

    def ttl
      channel_config.fetch :ttl, 360
    end

    def title
      channel_config.fetch(:title) { generated_title }
    end

    def generated_title
      uri = URI(url)

      nicer_path = uri.path.split('/')
      nicer_path.reject! { |part| part == '' }

      nicer_path.any? ? "#{uri.host}: #{nicer_path.join(' ').titleize}" : uri.host
    end

    def language
      channel_config.fetch :language, 'en'
    end

    def description
      channel_config.fetch :description, "Latest items from #{url}."
    end

    def url
      channel_config.dig :url
    end
    alias link url

    def time_zone
      channel_config.fetch :time_zone, 'UTC'
    end

    def json?
      channel_config.fetch :json, false
    end

    def headers
      global_config.fetch(:headers, {}).merge(channel_config.fetch(:headers, {}))
    end

    def attribute_options(name)
      feed_config.dig(:selectors).fetch(name, {}).merge(channel: channel_config)
    end

    def attribute?(name)
      attribute_names.include?(name)
    end

    def category_selectors
      categories = feed_config.dig(:selectors, :categories)
      return [] unless categories

      categories = categories.keep_if { |category| category.to_s != '' }
      categories.map!(&:to_sym)
      categories.uniq!

      categories
    end

    def selector(name)
      feed_config.dig(:selectors, name, :selector)
    end

    def attribute_names
      @attribute_names ||= feed_config.fetch(:selectors, {}).keys.tap { |attrs| attrs.delete(:items) }
    end

    private

    attr_reader :feed_config, :channel_config, :global_config
  end
end
