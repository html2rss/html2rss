# frozen_string_literal: true

module Html2rss
  class RssBuilder
    ##
    # Extracts channel information from
    # 1. the HTML document's <head>.
    # 2. the HTTP response
    class Channel
      ##
      #
      # @param response [Html2Rss::RequestService::Response]
      # @param time_zone [String]
      # @param overrides [Hash<Symbol, String>] - Optional, overrides for any channel attribute
      def initialize(response, time_zone:, overrides: {})
        @parsed_body = response.parsed_body
        @url = response.url
        @headers = response.headers
        @time_zone = time_zone
        @overrides = overrides
      end

      attr_reader :url

      def title
        @title ||= fetch_title
      end

      def description
        return overrides[:description] if overrides[:description]

        if parsed_body.is_a?(Nokogiri::HTML::Document)
          description = parsed_body.at_css('meta[name="description"]')&.[]('content')
        end

        description || "Latest items from #{url}"
      end

      def ttl
        return overrides[:ttl] if overrides[:ttl]

        ttl = headers['cache-control']&.match(/max-age=(\d+)/)&.[](1)
        return unless ttl

        ttl.to_i.fdiv(60).ceil
      end

      def language
        return overrides[:language] if overrides[:language]

        return unless parsed_body.is_a?(Nokogiri::HTML::Document)

        return parsed_body['lang'] if parsed_body.name == 'html' && parsed_body['lang']

        parsed_body.at_css('[lang]')&.[]('lang')
      end

      def author
        return overrides[:author] if overrides[:author]

        return unless parsed_body.is_a?(Nokogiri::HTML::Document)

        parsed_body.at_css('meta[name="author"]')&.[]('content')
      end

      def last_build_date = headers['last-modified'] || Time.now

      def image
        return overrides[:image] if overrides[:image]

        return unless parsed_body.is_a?(Nokogiri::HTML::Document)

        if (image_url = parsed_body.at_css('meta[property="og:image"]')&.[]('content'))
          Html2rss::Utils.sanitize_url(image_url)
        end
      end

      private

      attr_reader :parsed_body, :headers, :time_zone, :overrides

      def fetch_title
        return overrides[:title] if overrides[:title]
        return parsed_title if parsed_title

        Utils.titleized_channel_url(url)
      end

      def parsed_title
        return unless parsed_body.is_a?(Nokogiri::HTML::Document)

        title = parsed_body.at_css('head > title')&.text.to_s
        return if title.empty?

        title.gsub(/\s+/, ' ').strip
      end
    end
  end
end
