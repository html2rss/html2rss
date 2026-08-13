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

        # Maximum number of sub-sitemaps to fetch when fanning out through a sitemapindex.
        MAX_SUB_SITEMAPS = 3

        # @return [Symbol] scraper config key
        def self.options_key = :sitemap

        ##
        # Returns the number of request slots needed for sitemap discovery and fan-out.
        #
        # @param _opts [Hash] unused options
        # @return [Integer] number of follow-up requests needed
        def self.request_slots(_opts = {})
          1 + MAX_SUB_SITEMAPS
        end

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
        # @param body [String, nil] raw response body for direct sitemap XML parsing
        # @option _opts [Float] :min_priority minimum priority score (default: 0.3)
        # @option _opts [Integer] :max_age_days maximum entry age in days (default: 30)
        def initialize(parsed_body, url:, request_session: nil, body: nil, **opts)
          @parsed_body = parsed_body
          @body = body
          @url = Html2rss::Url.from_absolute(url)
          @request_session = request_session
          @min_priority = opts.fetch(:min_priority, Scraper::Sitemap::Parser::DEFAULT_MIN_PRIORITY)
          @max_age_days = opts.fetch(:max_age_days, Scraper::Sitemap::Parser::DEFAULT_MAX_AGE_DAYS)
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

        attr_reader :parsed_body, :body, :url, :request_session, :min_priority, :max_age_days

        def fetch_and_parse_entries
          entries = parse_direct_sitemap
          return entries unless entries.empty?

          xml_body = fetch_xml(target_sitemap_url)
          return [] unless xml_body

          parse_sitemap_xml(xml_body)
        rescue Html2rss::RequestService::RequestBudgetExceeded
          Log.warn("#{self.class}: sitemap fetch stopped — request budget exhausted")
          []
        end

        def parse_sitemap_xml(xml_body)
          result = Scraper::Sitemap::Parser.call(xml_body, min_priority:, max_age_days:)
          return fetch_sub_sitemaps(result.sub_sitemap_urls) if result.sub_sitemap_urls.any?

          result.entries
        end

        def parse_direct_sitemap
          return [] unless body
          return [] unless parsed_body.at_xpath('//*[local-name()="urlset" or local-name()="sitemapindex"]')

          Scraper::Sitemap::Parser.call(body, min_priority:, max_age_days:).entries
        end

        def fetch_sub_sitemaps(sub_urls)
          entries = []
          sub_urls.first(MAX_SUB_SITEMAPS).each do |sub_url|
            sub_entries = fetch_sub_sitemap_entries(sub_url)
            break unless sub_entries

            entries.concat(sub_entries)
          end
          entries
        end

        def fetch_sub_sitemap_entries(sub_url)
          xml = fetch_xml(sub_url)
          return [] unless xml

          Scraper::Sitemap::Parser.call(xml, min_priority:, max_age_days:).entries
        rescue Html2rss::RequestService::RequestBudgetExceeded
          Log.warn("#{self.class}: sitemap fan-out stopped — request budget exhausted")
          nil
        end

        def fetch_xml(target_url)
          return unless request_session && target_url

          response = request_session.follow_up(url: target_url, relation: :auto_source, origin_url: url)
          response&.body
        rescue Html2rss::RequestService::RequestBudgetExceeded
          raise
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
