# frozen_string_literal: true

require 'addressable'

module Html2rss
  class Config
    ##
    # Holds the configuration for the feed's channel options.
    # This contains:
    #
    # 1. the RSS channel attributes
    # 2. html2rss options like json or custom HTTP-headers for the request
    class Channel
      ##
      # @param config [Hash<Symbol, Object>]
      # @return [Set<String>] the required parameter names
      def self.required_params_for_config(config)
        config.each_with_object(Set.new) do |(_, value), required_params|
          required_params.merge(value.scan(/%<(\w+)>[s|d]/).flatten) if value.is_a?(String)
        end
      end

      ##
      # @param channel [Hash<Symbol, Object>]
      # @param params [Hash]
      def initialize(channel, params: {})
        raise ArgumentError, 'channel must be a hash' unless channel.is_a?(Hash)

        url = channel[:url]
        raise ArgumentError, 'missing key :url' unless url.is_a?(String) || url.is_a?(Addressable::URI)

        @config = process_params(channel, params.transform_keys(&:to_sym))
      end

      ##
      # The HTTP headers to use for the request.
      #
      # @return [Hash<Symbol, String>]
      def headers
        config.fetch(:headers, {})
      end

      ##
      # @return [String]
      def author
        config.fetch(:author, 'html2rss')
      end

      ##
      # @return [Integer]
      def ttl
        config.fetch(:ttl, 360)
      end

      ##
      # @return [String]
      def title
        config.fetch(:title) { Utils.titleized_url(url) }
      end

      ##
      # @return [String] language code
      def language
        config.fetch(:language, 'en')
      end

      ##
      # @return [String]
      def description
        config.fetch(:description) { "Latest items from #{url}." }
      end

      ##
      # @return [Addressable::URI]
      def url
        Addressable::URI.parse(config[:url]).normalize
      end

      ##
      # @return [String] time_zone name
      def time_zone
        config.fetch(:time_zone, 'UTC')
      end

      ##
      # @return [true, false]
      def json?
        config.fetch(:json, false)
      end

      private

      # @return [Hash<Symbol, Object>]
      attr_reader :config

      ##
      # @param config [Hash<Symbol, Object>]
      # @param params [Hash<Symbol, String>]
      # @return [nil]
      def assert_required_params_presence(config, params)
        missing_params = self.class.required_params_for_config(config) - params.keys.map(&:to_s)
        raise ParamsMissing, missing_params.to_a.join(', ') unless missing_params.empty?
      end

      ##
      # Sets the variables used in the feed config's channel.
      #
      # @param config [Hash<Symbol, Object>]
      # @param params [Hash<Symbol, Object>]
      # @return [Hash<Symbol, Object>]
      def process_params(config, params)
        assert_required_params_presence(config, params)
        config.transform_values do |value|
          value.is_a?(String) ? format(value, params) : value
        end
      end
    end
  end
end
