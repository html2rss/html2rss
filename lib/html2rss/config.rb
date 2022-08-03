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

    # Class to keep the XML Stylesheet attributes
    Stylesheet = Struct.new('Stylesheet', :href, :type, :media, keyword_init: true)

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
    # @param feed_config [Hash<Symbol, Object>]
    # @param global [Hash<Symbol, Object>]
    # @param params [Hash<Symbol, String>]
    def initialize(feed_config, global = {}, params = {})
      @channel = Channel.new(feed_config[:channel], params:)
      @selectors = Selectors.new(feed_config[:selectors])
      @global = global
    end

    ##
    # @param name [Symbol]
    # @return [Hash<Symbol, Object>]
    def selector_attributes_with_channel(name)
      @selectors.selector(name).to_h.merge(channel: @channel)
    end

    ##
    # @return [Hash]
    def headers
      @global.fetch(:headers, {}).merge @channel.headers
    end

    ##
    # @return [Array<Stylesheet>]
    def stylesheets
      @global.fetch(:stylesheets, []).map { |attributes| Stylesheet.new(attributes) }
    end

    # @return [Channel]
    attr_reader :channel
  end
end
