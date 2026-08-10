# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes articles from XML sitemaps explicitly linked in HTML or discovered via standard sitemap paths.
      class Sitemap
        include Enumerable

        # Selector for sitemap link tags in HTML head
        SITEMAP_LINK_SELECTOR = 'link[rel="sitemap"][href]'

        # @return [Symbol] scraper config key
        def self.options_key = :sitemap

        ##
        # @param parsed_body [Nokogiri::HTML::Document, nil] parsed document
        # @return [Boolean] whether the page links to a sitemap or is a sitemap
        def self.articles?(parsed_body)
          return false unless parsed_body

          !parsed_body.at_css(SITEMAP_LINK_SELECTOR).nil? ||
            !parsed_body.at_xpath('//*[local-name()="urlset" or local-name()="sitemapindex"]').nil?
        end

        ##
        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] canonical page URL
        # @param request_session [Html2rss::RequestSession, nil] shared request session for follow-up fetches
        # @option _opts [Float] :min_priority minimum priority score (default: 0.3)
        # @option _opts [Integer] :max_age_days maximum entry age in days (default: 30)
        def initialize(parsed_body, url:, request_session: nil, **opts)
          @parsed_body = parsed_body
          @url = Html2rss::Url.from_absolute(url)
          @request_session = request_session
          @min_priority = opts.fetch(:min_priority, Discovery::Sitemap::DEFAULT_MIN_PRIORITY)
          @max_age_days = opts.fetch(:max_age_days, Discovery::Sitemap::DEFAULT_MAX_AGE_DAYS)
        end

        ##
        # Yields article hashes from the sitemap.
        #
        # @yieldparam article [Hash{Symbol => Object}] normalized article hash
        # @return [Enumerator, void] enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?

          entries = fetch_and_parse_entries
          return if entries.empty?

          entries.each do |entry|
            article_hash = article_from_entry(entry)
            yield article_hash if article_hash
          end
        end

        private

        attr_reader :parsed_body, :url, :request_session, :min_priority, :max_age_days

        def fetch_and_parse_entries
          entries = parse_direct_sitemap
          return entries unless entries.empty?

          xml_body = fetch_sitemap_xml
          return [] unless xml_body

          Discovery::Sitemap.call(xml_body, min_priority:, max_age_days:)
        end

        def parse_direct_sitemap
          return [] unless parsed_body.at_xpath('//*[local-name()="urlset" or local-name()="sitemapindex"]')

          Discovery::Sitemap.call(parsed_body.to_s, min_priority:, max_age_days:)
        end

        def fetch_sitemap_xml
          return unless request_session && target_sitemap_url

          response = request_session.follow_up(url: target_sitemap_url, relation: :auto_source, origin_url: url)
          response&.body
        rescue Html2rss::Error => error
          Log.warn("#{self.class}: failed to fetch sitemap (#{error.class}: #{error.message})")
          nil
        end

        def target_sitemap_url
          link_tag = parsed_body.at_css(SITEMAP_LINK_SELECTOR)
          href = link_tag ? link_tag['href'] : '/sitemap.xml'
          Html2rss::Url.from_relative(href, url)
        end

        def article_from_entry(entry)
          return unless entry.url

          {
            url: entry.url,
            title: entry.title,
            published_at: entry.published_at
          }.compact
        end
      end
    end
  end
end
