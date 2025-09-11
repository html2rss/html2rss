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

      def url = @url ||= Html2rss::Url.from_relative(@response.url, @response.url)

      def description
        override_description = overrides[:description]
        return override_description unless override_description.to_s.empty?

        meta_description = extract_meta_description
        return format(DEFAULT_DESCRIPTION_TEMPLATE, url:) if meta_description.to_s.empty?

        meta_description
      end

      def ttl
        override_ttl = overrides[:ttl]
        return override_ttl if override_ttl

        if (ttl = headers['cache-control']&.match(/max-age=(\d+)/)&.[](1))
          return ttl.to_i.fdiv(60).ceil
        end

        DEFAULT_TTL_IN_MINUTES
      end

      def language
        override_language = overrides[:language]
        return override_language if override_language

        header_language = extract_header_language
        return header_language if header_language

        extract_html_language
      end

      def author
        override_author = overrides[:author]
        return override_author if override_author

        extract_meta_author
      end

      def last_build_date = headers['last-modified'] || Time.now

      def image
        override_image = overrides[:image]
        return override_image if override_image

        extract_meta_image
      end

      private

      attr_reader :overrides

      def parsed_body = @parsed_body ||= @response.parsed_body
      def headers = @headers ||= @response.headers
      def html_response? = @html_response ||= @response.html_response?

      def fetch_title
        override_title = overrides[:title]
        return override_title if override_title
        return parsed_title if parsed_title

        url.channel_titleized
      end

      def parsed_title
        return unless html_response?

        title = parsed_body.at_css('head > title')&.text.to_s
        return if title.empty?

        title.gsub(/\s+/, ' ').strip
      end

      def extract_meta_description
        return nil unless html_response?

        parsed_body.at_css('meta[name="description"]')&.[]('content')
      end

      def extract_header_language
        language_code = headers['content-language']&.match(/^([a-z]{2})/)
        language_code&.[](0)
      end

      def extract_html_language
        return nil unless html_response?

        parsed_body['lang'] || parsed_body.at_css('[lang]')&.[]('lang')
      end

      def extract_meta_author
        return nil unless html_response?

        parsed_body.at_css('meta[name="author"]')&.[]('content')
      end

      def extract_meta_image
        return nil unless html_response?

        image_url = parsed_body.at_css('meta[property="og:image"]')&.[]('content')
        Url.sanitize(image_url) if image_url
      end
    end
  end
end
