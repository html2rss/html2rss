# frozen_string_literal: true

require 'active_support/core_ext/hash'

module Html2rss
  ##
  # The Config class abstracts from the config data structure and
  # provides default values.
  class Config
    ##
    # @param feed_config [Hash<Symbol, Object>]
    # @param global_config [Hash<Symbol, Object>]
    def initialize(feed_config, global_config = {})
      @global_config = global_config.deep_symbolize_keys
      @feed_config = feed_config.deep_symbolize_keys
      @channel_config = @feed_config.fetch(:channel, {})
    end

    ##
    # @return [String]
    def author
      channel_config.fetch :author, 'html2rss'
    end

    ##
    # @return [Integer]
    def ttl
      channel_config.fetch :ttl, 360
    end

    ##
    # @return [String]
    def title
      channel_config.fetch(:title) { generated_title }
    end

    ##
    # @return [String]
    def generated_title
      uri = URI(url)

      nicer_path = uri.path.split('/')
      nicer_path.reject! { |part| part == '' }

      nicer_path.any? ? "#{uri.host}: #{nicer_path.join(' ').titleize}" : uri.host
    end

    ##
    # @return [String] language code
    def language
      channel_config.fetch :language, 'en'
    end

    ##
    # @return [String]
    def description
      channel_config.fetch :description, "Latest items from #{url}."
    end

    ##
    # @return [String]
    def url
      channel_config[:url]
    end
    alias link url

    ##
    # @return [String] time_zone name
    def time_zone
      channel_config.fetch :time_zone, 'UTC'
    end

    ##
    # @return [true, false]
    def json?
      channel_config.fetch :json, false
    end

    ##
    # @return [Hash]
    def headers
      global_config.fetch(:headers, {}).merge(channel_config.fetch(:headers, {}))
    end

    ##
    # @param name [Symbol]
    # @return [Hash]
    def attribute_options(name)
      feed_config[:selectors].fetch(name, {}).merge(channel: channel_config)
    end

    ##
    # @param name [Symbol]
    # @return [true, false]
    def attribute?(name)
      attribute_names.include?(name)
    end

    ##
    # @return [Array<Symbol>]
    def category_selectors
      categories = feed_config.dig(:selectors, :categories)
      return [] unless categories

      categories = categories.keep_if { |category| category.to_s != '' }
      categories.map!(&:to_sym)
      categories.uniq!

      categories
    end

    ##
    # @param name [Symbol]
    # @return [String]
    def selector(name)
      feed_config.dig(:selectors, name, :selector)
    end

    ##
    # @return [Array<String>]
    def attribute_names
      @attribute_names ||= feed_config.fetch(:selectors, {}).keys.tap { |attrs| attrs.delete(:items) }
    end

    ##
    # @return [Symbol]
    def items_order
      feed_config.dig(:selectors, :items, :order)&.to_sym
    end

    private

    # @return [Hash<Symbol, Object>]
    attr_reader :feed_config, :channel_config, :global_config
  end
end
