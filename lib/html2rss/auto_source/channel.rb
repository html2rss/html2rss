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
      # @param url [Addressable::URI] The URL of the channel.
      # @param headers [Hash<String, String>] the http headers
      # @param articles [Array<Html2rss::AutoSource::Article>] The articles.
      def initialize(parsed_body, url:, headers:, articles: [], stylesheets: [])
        @parsed_body = parsed_body
        @url = url
        @headers = headers
        @articles = articles
        @stylesheets = stylesheets
      end

      attr_writer :articles
      attr_reader :stylesheets

      def url = @url.normalize.to_s

      def title
        @title ||= if (title = parsed_body.at_css('head > title')&.text.to_s) && !title.empty?
                     title.gsub(/\s+/, ' ').strip
                   else
                     Utils.titleized_channel_url(@url)
                   end
      end

      def description = parsed_body.at_css('meta[name="description"]')&.[]('content')
      def last_build_date = headers['last-modified']

      def language
        return parsed_body['lang'] if parsed_body.name == 'html' && parsed_body['lang']

        parsed_body.at_css('[lang]')&.[]('lang')
      end

      def image
        url = parsed_body.at_css('meta[property="og:image"]')&.[]('content')
        Html2rss::Utils.sanitize_url(url) if url
      end

      def ttl
        ttl = headers['cache-control']&.match(/max-age=(\d+)/)&.[](1)
        return unless ttl

        ttl.to_i.fdiv(60).ceil
      end

      def generator
        "html2rss V. #{::Html2rss::VERSION} (using auto_source scrapers: #{scraper_counts})"
      end

      private

      attr_reader :parsed_body, :headers

      def scraper_counts
        scraper_counts = +''

        @articles.each_with_object(Hash.new(0)) { |article, counts| counts[article.scraper] += 1 }
                 .each do |klass, count|
          scraper_counts.concat("[#{klass.to_s.gsub('Html2rss::AutoSource::Scraper::', '')}=#{count}]")
        end

        scraper_counts
      end
    end
  end
end
