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
    # Thrown when a feed config (Hash) does not contain a value at `:channel`.
    class ChannelMissing < StandardError; end

    def_delegator :@channel, :author
    def_delegator :@channel, :ttl
    def_delegator :@channel, :title
    def_delegator :@channel, :language
    def_delegator :@channel, :description
    def_delegator :@channel, :url
    def_delegator :@channel, :url, :link
    def_delegator :@channel, :time_zone
    def_delegator :@channel, :json?

    def_delegator :@selectors, :attribute_names
    def_delegator :@selectors, :attribute?
    def_delegator :@selectors, :category_selectors
    def_delegator :@selectors, :guid_selectors
    def_delegator :@selectors, :items_order
    def_delegator :@selectors, :selector

    ##
    # @param feed_config [Hash<Symbol, Object>]
    # @param global [Hash<Symbol, Object>]
    # @param params [Hash<Symbol, String>]
    def initialize(feed_config, global = {}, params = {})
      @channel = Channel.new(feed_config[:channel], params: params)
      @selectors = Selectors.new(feed_config[:selectors])
      @global = global
    end

    ##
    # @param name [Symbol]
    # @return [Hash]
    def selector_attributes_with_channel(name)
      @selectors.selector_attributes(name).merge(channel: @channel)
    end

    ##
    # @return [Hash]
    def headers
      @global.fetch(:headers, {}).merge @channel.headers
    end

    ##
    # @return [Array<Hash>]
    def stylesheets
      @global.fetch(:stylesheets, [])
    end

    attr_reader :channel
  end
end
