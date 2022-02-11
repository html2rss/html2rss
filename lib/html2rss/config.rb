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

    def_delegator :@global_config, :stylesheets
    def_delegator :@selectors, :attribute_names
    def_delegator :@selectors, :attribute_options
    def_delegator :@selectors, :attribute?
    def_delegator :@selectors, :category_selectors
    def_delegator :@selectors, :guid_selectors
    def_delegator :@selectors, :items_order
    def_delegator :@selectors, :selector

    ##
    # @param feed_config [Hash<Symbol, Object>]
    # @param global_config [Hash<Symbol, Object>]
    # @param params [Hash<Symbol, String>]
    def initialize(feed_config, global_config = {}, params = {})
      @global_config = Global.new(global_config)
      @channel_config = feed_config.fetch(:channel)
      @feed_config = Feed.new(feed_config, params, @channel_config)
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

      host = uri.host
      nicer_path.any? ? "#{host}: #{nicer_path.map(&:capitalize).join(' ')}" : host
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
      # TODO: move to feed config, avoid fetch call (provide method)
      @global_config.headers.merge(channel_config.fetch(:headers, {}))
    end

    private

    # @return [Hash<Symbol, Object>]
    attr_reader :channel_config
  end
end
