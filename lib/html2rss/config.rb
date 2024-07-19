# frozen_string_literal: true

require 'forwardable'

module Html2rss
  ##
  # The Config class abstracts from the config data structure and
  # provides default values.
  class Config
    extend Forwardable

    ##
    # The Error class to be thrown when a feed config requires params, but none
    # were passed to Config.
    class ParamsMissing < StandardError; end

    ##
    # Thrown when the feed config does not contain a value at `:channel`.
    class ChannelMissing < StandardError; end

    # Struct to store XML Stylesheet attributes
    Stylesheet = Struct.new(:href, :type, :media, keyword_init: true)

    def_delegator :@channel, :author
    def_delegator :@channel, :ttl
    def_delegator :@channel, :title
    def_delegator :@channel, :language
    def_delegator :@channel, :description
    def_delegator :@channel, :url
    def_delegator :@channel, :url, :link
    def_delegator :@channel, :time_zone
    def_delegator :@channel, :json?

    def_delegator :@selectors, :item_selector_names
    def_delegator :@selectors, :selector?
    def_delegator :@selectors, :category_selector_names
    def_delegator :@selectors, :guid_selector_names
    def_delegator :@selectors, :items_order
    def_delegator :@selectors, :selector_string

    ##
    # Initializes the Config object with feed configuration, global settings, and parameters.
    #
    # @param feed_config [Hash<Symbol, Object>] The configuration hash containing `:channel` and `:selectors`.
    # @param global [Hash<Symbol, Object>] Global settings hash.
    # @param params [Hash<Symbol, String>] Parameters hash.
    def initialize(feed_config, global = {}, params = {})
      channel_config = feed_config[:channel]
      raise ChannelMissing, 'Channel configuration is missing in feed_config' unless channel_config

      @channel = Channel.new(channel_config, params:)
      @selectors = Selectors.new(feed_config[:selectors])
      @global = global
    end

    ##
    # Retrieves selector attributes merged with channel attributes.
    #
    # @param name [Symbol] Selector name.
    # @return [Hash<Symbol, Object>] Merged attributes hash.
    def selector_attributes_with_channel(name)
      @selectors.selector(name).to_h.merge(channel: @channel)
    end

    ##
    # Retrieves headers merged from global settings and channel headers.
    #
    # @return [Hash] Merged headers hash.
    def headers
      @global.fetch(:headers, {}).merge(@channel.headers)
    end

    ##
    # Retrieves stylesheets from global settings.
    #
    # @return [Array<Stylesheet>] Array of Stylesheet structs.
    def stylesheets
      @global.fetch(:stylesheets, []).map { |attributes| Stylesheet.new(attributes) }
    end

    # Provides read-only access to the channel object.
    attr_reader :channel
  end
end
