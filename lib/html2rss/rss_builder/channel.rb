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
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
      # @param url [Addressable::URI] The URL of the channel.
      # @param headers [Hash<String, String>] the http response headers
      def initialize(parsed_body, url:, headers:, time_zone: 'UTC', overrides: {})
        @parsed_body = parsed_body
        @url = url
        @headers = headers
        @time_zone = time_zone
        @overrides = overrides
      end

      attr_writer :articles
      attr_reader :time_zone, :overrides

      def url = @url.normalize.to_s

      def title
        @title ||= if overrides[:title]
                     overrides[:title]
                   elsif (title = parsed_body.at_css('head > title')&.text.to_s) && !title.empty?
                     title.gsub(/\s+/, ' ').strip
                   else
                     Utils.titleized_channel_url(@url)
                   end
      end

      def description
        overrides[:description] ||
          parsed_body.at_css('meta[name="description"]')&.[]('content') ||
          "Latest items from #{url}."
      end

      def ttl
        return overrides[:ttl] if overrides[:ttl]

        ttl = headers['cache-control']&.match(/max-age=(\d+)/)&.[](1)
        return unless ttl

        ttl.to_i.fdiv(60).ceil
      end

      def language
        return overrides[:language] if overrides[:language]
        return parsed_body['lang'] if parsed_body.name == 'html' && parsed_body['lang']

        parsed_body.at_css('[lang]')&.[]('lang')
      end

      def author
        overrides[:author] ||
          parsed_body.at_css('meta[name="author"]')&.[]('content')
      end

      def last_build_date = headers['last-modified'] || Time.now

      def image
        url = parsed_body.at_css('meta[property="og:image"]')&.[]('content')
        Html2rss::Utils.sanitize_url(url) if url
      end

      private

      attr_reader :parsed_body, :headers
    end
  end
end
