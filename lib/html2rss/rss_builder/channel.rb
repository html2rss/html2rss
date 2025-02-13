# frozen_string_literal: true

module Html2rss
  class RssBuilder
    ##
    # Extracts channel information from
    # 1. the HTML document's <head>.
    # 2. the HTTP response
    class Channel
      DEFAULT_TTL_IN_MINUTES = 360
      DEFAULT_DESCRIPTION_TEMPLATE = 'Latest items from %<url>s'

      ##
      #
      # @param response [Html2rss::RequestService::Response]
      # @param overrides [Hash<Symbol, String>] - Optional, overrides for any channel attribute
      def initialize(response, overrides: {})
        @response = response
        @overrides = overrides
      end

      def title
        @title ||= fetch_title
      end

      def url = @url ||= @response.url

      def description
        return overrides[:description] unless overrides[:description].to_s.empty?

        description = parsed_body.at_css('meta[name="description"]')&.[]('content') if html_response?

        return format(DEFAULT_DESCRIPTION_TEMPLATE, url: url) if description.to_s.empty?

        description
      end

      def ttl
        return overrides[:ttl] if overrides[:ttl]

        if (ttl = headers['cache-control']&.match(/max-age=(\d+)/)&.[](1))
          return ttl.to_i.fdiv(60).ceil
        end

        DEFAULT_TTL_IN_MINUTES
      end

      def language
        return overrides[:language] if overrides[:language]

        if (language_code = headers['content-language']&.match(/^([a-z]{2})/))
          return language_code[0]
        end

        return unless html_response?

        parsed_body['lang'] || parsed_body.at_css('[lang]')&.[]('lang')
      end

      def author
        return overrides[:author] if overrides[:author]

        return unless html_response?

        parsed_body.at_css('meta[name="author"]')&.[]('content')
      end

      def last_build_date = headers['last-modified'] || Time.now

      def image
        return overrides[:image] if overrides[:image]

        return unless html_response?

        if (image_url = parsed_body.at_css('meta[property="og:image"]')&.[]('content'))
          Html2rss::Utils.sanitize_url(image_url)
        end
      end

      private

      attr_reader :overrides

      def parsed_body = @parsed_body ||= @response.parsed_body
      def headers = @headers ||= @response.headers
      def html_response? = @html_response ||= @response.html_response?

      def fetch_title
        return overrides[:title] if overrides[:title]
        return parsed_title if parsed_title

        Utils.titleized_channel_url(url)
      end

      def parsed_title
        return unless html_response?

        title = parsed_body.at_css('head > title')&.text.to_s
        return if title.empty?

        title.gsub(/\s+/, ' ').strip
      end
    end
  end
end
