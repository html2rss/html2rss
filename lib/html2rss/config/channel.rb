module Html2rss
  class Config
    ##
    # Holds the configuration for the feeds channel options.
    # This contains
    #
    # 1. the RSS channel attributes
    # 2. html2rss options like json or custom HTTP-headers for the request
    class Channel
      def initialize(feed_config = {})
        @channel_config = feed_config.fetch(:channel)
      end

      ##
      # The HTTP headers to use for the request.
      #
      # @return [Hash<Symbol, String>]
      def headers
        channel_config.fetch :headers, {}
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

      private

      # @return [Hash<Symbol, Object>]
      attr_reader :channel_config
    end
  end
end
