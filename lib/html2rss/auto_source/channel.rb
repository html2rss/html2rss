# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Extracts channel information from
    # 1. the HTML document's <head>.
    # 2. the HTTP response
    class Channel
      ##
      #
      # @param parsed_body [Nokogiri::HTML::Document] The parsed HTML document.
      # @param response [Faraday::Response] The URL of the HTML document.
      def initialize(parsed_body, url:, response:, articles: [])
        @parsed_body = parsed_body
        @url = url
        @response = response
        @articles = articles
      end

      def url = extract_url
      def title = extract_title
      def language = extract_language
      def description = extract_description
      def image = extract_image
      def ttl = extract_ttl
      def last_build_date = response.headers['last-modified']

      def generator
        "html2rss V. #{::Html2rss::VERSION} (using auto_source scrapers: #{scraper_counts})"
      end

      private

      attr_reader :parsed_body, :response

      def extract_url
        @url.normalize.to_s
      end

      def extract_title
        parsed_body.at_css('head > title')&.text
      end

      def extract_language
        return parsed_body['lang'] if parsed_body.name == 'html' && parsed_body['lang']

        parsed_body.at_css('[lang]')&.[]('lang')
      end

      def extract_description
        parsed_body.at_css('meta[name="description"]')&.[]('content') || ''
      end

      def extract_image
        url = parsed_body.at_css('meta[property="og:image"]')&.[]('content')
        Html2rss::Utils.sanitize_url(url) if url
      end

      def extract_ttl
        ttl = response.headers['cache-control']&.match(/max-age=(\d+)/)&.[](1)
        return unless ttl

        ttl.to_i.fdiv(60).ceil
      end

      def scraper_counts
        scraper_counts = +''

        @articles.each_with_object(Hash.new(0)) { |article, counts| counts[article.generated_by] += 1 }
                 .each do |klass, count|
          scraper_counts.concat("[#{klass.to_s.gsub('Html2rss::AutoSource::Scraper::', '')}=#{count}]")
        end

        scraper_counts
      end
    end
  end
end
