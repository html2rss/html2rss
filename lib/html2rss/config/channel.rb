# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Holds the configuration for the feed's channel options.
    # This contains:
    #
    # 1. the RSS channel attributes
    # 2. html2rss options like json or custom HTTP-headers for the request
    #
    class Channel
      def initialize(channel, params: {})
        raise ArgumentError, 'channel must be a hash' unless channel.is_a?(Hash)
        raise ArgumentError, 'missing key :url' unless channel[:url].is_a?(String)

        symbolized_params = params.transform_keys(&:to_sym)

        @config = process_params channel, symbolized_params
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
        config.fetch :author, 'html2rss'
      end

      ##
      # @return [Integer]
      def ttl
        config.fetch :ttl, 360
      end

      ##
      # @return [String]
      def title
        config.fetch(:title) { generated_title }
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
        config.fetch :language, 'en'
      end

      ##
      # @return [String]
      def description
        config.fetch(:description) { "Latest items from #{url}." }
      end

      ##
      # @return [String]
      def url
        config[:url]
      end

      ##
      # @return [String] time_zone name
      def time_zone
        config.fetch :time_zone, 'UTC'
      end

      ##
      # @return [true, false]
      def json?
        config.fetch :json, false
      end

      ##
      # Returns the dynamic parameter names which are required to use the feed config.
      #
      # @param config [Hash<Symbol, Object>]
      # @return [Set] containing Strings (the parameter names)
      def self.required_params_for_config(config)
        Set.new.tap do |required_params|
          config.each_key do |attribute_name|
            next unless config[attribute_name].is_a?(String)

            required_params.merge config[attribute_name].scan(/%<([\w_\d]+)>(\w)?/).to_h.keys
          end
        end
      end

      private

      # @return [Hash<Symbol, Object>]
      attr_reader :config

      ##
      # @param feed_config [Hash<Symbol, Object>]
      # @param params [Hash<Symbol, String>]
      # @return [nil]
      def assert_required_params_presence(config, params)
        missing_params = self.class.required_params_for_config(config) - params.keys.map(&:to_s)

        raise ParamsMissing, missing_params.to_a.join(', ') if missing_params.size.positive?
      end

      ##
      # Sets the variables used in the feed config's channel.
      #
      # @param config [Hash<Symbol, Object>]
      # @param params [Hash<Symbol, Object>]
      # @return [Hash<Symbol, Object>]
      def process_params(config, params)
        assert_required_params_presence(config, params)

        return config if params.keys.none?

        config.each_key do |attribute_name|
          next unless config[attribute_name].is_a?(String)

          config[attribute_name] = format(config[attribute_name], params)
        end

        config
      end
    end
  end
end
