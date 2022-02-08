# frozen_string_literal: true

begin
  require 'active_support/isolated_execution_state'
rescue LoadError => e
  puts e.message
end

require 'active_support/core_ext/hash'

module Html2rss
  ##
  # The Config class abstracts from the config data structure and
  # provides default values.
  class Config
    ##
    # The Error class to be thrown when a feed config requires params, but none
    # were passed to Config.
    class ParamsMissing < StandardError; end

    ##
    # Thrown when a feed config (Hash) does not contain a value at `:channel`.
    class ChannelMissing < StandardError; end

    ##
    # @param feed_config [Hash<Symbol, Object>]
    # @param global_config [Hash<Symbol, Object>]
    # @param params [Hash<Symbol, String>]
    def initialize(feed_config, global_config = {}, params = {})
      symbolized_params = params.transform_keys(&:to_sym)
      feed_config = feed_config.deep_symbolize_keys

      assert_required_params_presence(feed_config, symbolized_params)

      @global_config = global_config.deep_symbolize_keys
      @feed_config = process_params(feed_config, symbolized_params)
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

      host = uri.host
      nicer_path.any? ? "#{host}: #{nicer_path.join(' ').titleize}" : host
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
    # @return [Array<Hash>]
    def stylesheets
      global_config.fetch(:stylesheets, [])
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
      selector_names_for(:categories)
    end

    ##
    # @return [Array<Symbol>]
    def guid_selectors
      selector_names_for(:guid, default: :title_or_description)
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

    ##
    # Returns the dynamic parameter names which are required to use the feed config.
    #
    # @param feed_config [Hash<Symbol, Object>]
    # @return [Set] containing Strings (the parameter names)
    def self.required_params_for_feed_config(feed_config)
      raise ChannelMissing, 'feed config misses :channel key' unless feed_config[:channel]

      Set.new.tap do |required_params|
        feed_config[:channel].each_key do |attribute_name|
          next unless feed_config[:channel][attribute_name].is_a?(String)

          required_params.merge feed_config[:channel][attribute_name].scan(/%<([\w_\d]+)>(\w)?/).to_h.keys
        end
      end
    end

    private

    # @return [Hash<Symbol, Object>]
    attr_reader :feed_config, :channel_config, :global_config

    ##
    # @param feed_config [Hash<Symbol, Object>]
    # @param params [Hash<Symbol, String>]
    # @return [nil]
    def assert_required_params_presence(feed_config, params)
      missing_params = Config.required_params_for_feed_config(feed_config) - params.keys.map(&:to_s)

      raise ParamsMissing, missing_params.to_a.join(', ') if missing_params.size.positive?
    end

    ##
    # Sets the variables used in the feed config's channel.
    #
    # @param feed_config [Hash<Symbol, Object>]
    # @param params [Hash<Symbol, Object>]
    # @return [Hash<Symbol, Object>]
    def process_params(feed_config, params)
      return feed_config if params.keys.none?

      feed_config[:channel].each_key do |attribute_name|
        next unless feed_config[:channel][attribute_name].is_a?(String)

        feed_config[:channel][attribute_name] = format(feed_config[:channel][attribute_name], params)
      end

      feed_config
    end

    ##
    # Returns the selector names for selector `name`. If none, returns [default].
    # @param name [Symbol]
    # @param default [String, Symbol]
    # @return [Array<Symbol>]
    def selector_names_for(name, default: nil)
      feed_config[:selectors].fetch(name) { Array(default) }.tap do |array|
        array.reject! { |entry| entry.to_s == '' }
        array.map!(&:to_sym)
        array.uniq!
      end
    end
  end
end
